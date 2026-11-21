#!/usr/bin/env python3
"""
Arno Link Desktop - control the ARNO OS Desk Buddy from a PC.   Created By- Arnod
Connects by USB cable (serial) OR Bluetooth (BLE). Windows / Linux / macOS.
"""
import asyncio, json, os, queue, sys, threading, time, tkinter as tk
from tkinter import ttk, messagebox, simpledialog

try:
    import serial, serial.tools.list_ports
except Exception:
    serial = None
try:
    from bleak import BleakClient, BleakScanner
except Exception:
    BleakClient = None

SVC = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
RX = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
TX = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
FACES = ['Smirk','Winking Heart','Laughing','Crying','Enraged','Mind Blown','Starry Eyed','Thinking','Yawning','Skeptic','Sweating','In Love','Determined','Boo','Silly','Cool','Ninja','Robot','Cat','Nerd','Vampire','Ghost Panic','Angel','Devil','Money Eyes','Alien','Victorious','Teasing','Exhausted','Loading','Glitch','Pixel Heart','Cyber Shield','Matrix Code','Neon Spiral','Equalizer','Radar','Battery Low','Charging','WiFi Search','Bluetooth','Terminal','Skull','Crosshair','Gamepad','Rocket','Atom','Infinity','Biohazard','Radioactive','Fire','Water Drop','Lightning','Snowflake','Sun Rays','Crescent Moon','Cloud Rain','Wind Gust','Compass','Bullseye','Sleepy','Surprised','Kiss','Dizzy','Party Hat','Pirate','Sick','Normal','Coffee','Music Notes']
CFG = os.path.join(os.path.expanduser("~"), ".arno_link_desktop.json")


def media_key(name):
    """Play/pause/next/prev on this PC (Windows media keys)."""
    codes = {"pp": 0xB3, "next": 0xB0, "prev": 0xB1}
    if sys.platform.startswith("win"):
        import ctypes
        ctypes.windll.user32.keybd_event(codes[name], 0, 0, 0)
        ctypes.windll.user32.keybd_event(codes[name], 0, 2, 0)


class Link:
    """One object for both transports. Incoming lines go to .inbox"""
    def __init__(self):
        self.inbox = queue.Queue()
        self.mode = None            # "usb" | "ble"
        self.ser = None
        self.loop = None
        self.client = None
        self.alive = False
        self.buf = ""
        self._outq = queue.Queue()

    # ---- USB
    def open_usb(self, port):
        self.close()
        s = serial.Serial()
        s.port, s.baudrate, s.timeout = port, 115200, 0.2
        s.dtr = False; s.rts = False      # do not reset the board when opening
        s.open()
        self.ser = s; self.mode = "usb"; self.alive = True
        threading.Thread(target=self._usb_reader, daemon=True).start()
        threading.Thread(target=self._usb_keepalive, daemon=True).start()
        self.send("PING"); self.send("PN|" + os.environ.get("COMPUTERNAME", os.environ.get("HOSTNAME", "PC")))
        self.send("I?"); self.send("EV?")

    def _usb_reader(self):
        buf = b""
        while self.alive and self.ser:
            try:
                data = self.ser.read(256)
            except Exception:
                break
            if data:
                buf += data
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    line = line.decode("utf-8", "ignore").strip()
                    if line: self.inbox.put(line)
        if self.alive: self.inbox.put("X|lost")
        self.alive = False

    def _usb_keepalive(self):
        while self.alive:
            time.sleep(3)
            self.send("PING")

    # ---- Bluetooth
    def open_ble(self, address):
        self.close()
        self.mode = "ble"; self.alive = True
        self.loop = asyncio.new_event_loop()
        threading.Thread(target=self._ble_thread, args=(address,), daemon=True).start()

    def _ble_thread(self, address):
        asyncio.set_event_loop(self.loop)
        self.loop.run_until_complete(self._ble_main(address))

    async def _ble_main(self, address):
        try:
            async with BleakClient(address, timeout=20) as c:
                self.client = c
                def on_notify(_, data):
                    self.buf += data.decode("utf-8", "ignore")
                    while "\n" in self.buf:
                        line, self.buf = self.buf.split("\n", 1)
                        if line.strip(): self.inbox.put(line.strip())
                await c.start_notify(TX, on_notify)
                self.inbox.put("X|ble-connected")
                for cmd in ("PN|" + os.environ.get("COMPUTERNAME", "PC"), "I?", "EV?"):
                    await c.write_gatt_char(RX, (cmd + "\n").encode(), response=True)
                while self.alive and c.is_connected:
                    try:
                        cmd = self._outq.get_nowait()
                        await c.write_gatt_char(RX, (cmd + "\n").encode(), response=True)
                    except queue.Empty:
                        await asyncio.sleep(0.05)
        except Exception as e:
            self.inbox.put("X|error " + str(e))
        self.client = None
        if self.alive: self.inbox.put("X|lost")
        self.alive = False

    # ---- common
    def send(self, line):
        if self.mode == "usb" and self.ser:
            try:
                self.ser.write((line + "\n").encode()); self.ser.flush()
            except Exception:
                pass
        elif self.mode == "ble" and self.alive:
            self._outq.put(line)

    def close(self):
        self.alive = False
        if self.ser:
            try: self.ser.close()
            except Exception: pass
        self.ser = None; self.mode = None
        time.sleep(0.1)


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Arno Link Desktop  -  Created By- Arnod")
        self.geometry("760x640"); self.minsize(700, 560)
        self.link = Link(); self.info = {}; self.ble_devs = {}
        self.cfg = {}
        try: self.cfg = json.load(open(CFG))
        except Exception: pass
        self.events = self.cfg.get("events", [])
        self.status = tk.StringVar(value="Not connected")
        self._build()
        self.after(100, self._poll)

    # ------------- UI
    def _build(self):
        top = ttk.Frame(self); top.pack(fill="x", padx=10, pady=8)
        ttk.Label(top, text="Arno Link Desktop", font=("Segoe UI", 15, "bold")).pack(side="left")
        ttk.Label(top, textvariable=self.status, foreground="#1a8f6a").pack(side="right")
        nb = ttk.Notebook(self); nb.pack(fill="both", expand=True, padx=10, pady=4)
        self.t_conn, self.t_ctl, self.t_faces, self.t_tools, self.t_set = [ttk.Frame(nb) for _ in range(5)]
        for f, n in ((self.t_conn, "Connect"), (self.t_ctl, "Control"), (self.t_faces, "Faces"), (self.t_tools, "Tools"), (self.t_set, "Settings")):
            nb.add(f, text=n)
        self._tab_connect(); self._tab_control(); self._tab_faces(); self._tab_tools(); self._tab_settings()
        ttk.Label(self, text="Created By- Arnod", foreground="#888").pack(pady=4)

    def _tab_connect(self):
        f = self.t_conn
        a = ttk.LabelFrame(f, text="USB cable (wired)"); a.pack(fill="x", padx=10, pady=10)
        self.port = ttk.Combobox(a, state="readonly", width=40); self.port.pack(side="left", padx=8, pady=8)
        ttk.Button(a, text="Refresh", command=self.refresh_ports).pack(side="left")
        ttk.Button(a, text="Connect USB", command=self.conn_usb).pack(side="left", padx=8)
        b = ttk.LabelFrame(f, text="Bluetooth"); b.pack(fill="x", padx=10, pady=10)
        self.ble = ttk.Combobox(b, state="readonly", width=40); self.ble.pack(side="left", padx=8, pady=8)
        ttk.Button(b, text="Scan", command=self.scan_ble).pack(side="left")
        ttk.Button(b, text="Connect Bluetooth", command=self.conn_ble).pack(side="left", padx=8)
        ttk.Button(f, text="Disconnect", command=self.disconnect).pack(pady=6)
        self.log = tk.Text(f, height=12, state="disabled", bg="#101418", fg="#bde"); self.log.pack(fill="both", expand=True, padx=10, pady=6)
        self.refresh_ports()
        if serial is None: self.say("pyserial missing: pip install pyserial")
        if BleakClient is None: self.say("bleak missing: pip install bleak (needed for Bluetooth)")

    def _tab_control(self):
        f = self.t_ctl
        g = ttk.LabelFrame(f, text="Show on Desk Buddy"); g.pack(fill="x", padx=10, pady=8)
        items = [("Time", "MTIME"), ("Analog clock", "MCLOCK"), ("Weather", "MWEATHER"), ("3-day forecast", "MFORECAST"), ("Location", "MLOC"), ("System info", "MINFO"),
                 ("Sleep clock", "MSLEEP"), ("Sleepy face", "MSLEEPY"), ("Right manual", "MMAN1"), ("Left manual", "MMAN2"), ("Stopwatch", "MSW"), ("Countdown", "MCD")]
        for i, (t, c) in enumerate(items):
            ttk.Button(g, text=t, command=lambda c=c: self.link.send(c)).grid(row=i // 4, column=i % 4, padx=4, pady=4, sticky="ew")
        for k in range(4): g.columnconfigure(k, weight=1)
        p = ttk.LabelFrame(f, text="Virtual touch pads"); p.pack(fill="x", padx=10, pady=8)
        for col, (name, side, extra) in enumerate((("LEFT PAD", "L", [("hold 3s", "H")]), ("RIGHT PAD", "R", [("hold 1s", "H"), ("hold 5s", "L")]))):
            box = ttk.Frame(p); box.grid(row=0, column=col, padx=12, pady=8, sticky="n")
            ttk.Button(box, text=name + "  (1 tap)", width=22, command=lambda s=side: self.link.send(f"PAD|{s}|1")).pack(ipady=14)
            row = ttk.Frame(box); row.pack(pady=4)
            for n in ([2, 3, 4, 5] if side == "L" else [2, 3, 4]):
                ttk.Button(row, text=f"{n}x", width=4, command=lambda s=side, n=n: self.link.send(f"PAD|{s}|{n}")).pack(side="left")
            for t, e in extra:
                ttk.Button(row, text=t, width=8, command=lambda s=side, e=e: self.link.send(f"PAD|{s}|{e}")).pack(side="left", padx=2)
        d = ttk.LabelFrame(f, text="Dino game"); d.pack(fill="x", padx=10, pady=8)
        ttk.Button(d, text="Open", command=lambda: self.link.send("MDINO")).pack(side="left", padx=6, pady=6)
        ttk.Button(d, text="JUMP / START", command=lambda: self.link.send("PAD|L|1")).pack(side="left", padx=6, ipady=6)
        ttk.Button(d, text="Quit", command=lambda: self.link.send("PAD|R|1")).pack(side="left", padx=6)
        self.bind("<space>", lambda e: self.link.send("PAD|L|1"))

    def _tab_faces(self):
        f = self.t_faces
        lb = tk.Listbox(f, font=("Segoe UI", 11)); lb.pack(side="left", fill="both", expand=True, padx=10, pady=10)
        for i, n in enumerate(FACES): lb.insert("end", f"{i + 1:>2}.  {n}")
        lb.bind("<<ListboxSelect>>", lambda e: self.link.send(f"F{lb.curselection()[0]}") if lb.curselection() else None)
        sb = ttk.Scrollbar(f, command=lb.yview); sb.pack(side="right", fill="y"); lb.config(yscrollcommand=sb.set)

    def _tab_tools(self):
        f = self.t_tools
        m = ttk.LabelFrame(f, text="Send text to Desk Buddy"); m.pack(fill="x", padx=10, pady=8)
        self.msg = ttk.Entry(m); self.msg.pack(side="left", fill="x", expand=True, padx=6, pady=8)
        ttk.Button(m, text="Send", command=lambda: self.link.send("T|" + self.msg.get().replace("\n", " "))).pack(side="left", padx=6)
        c = ttk.LabelFrame(f, text="Countdown / stopwatch"); c.pack(fill="x", padx=10, pady=8)
        self.cd = ttk.Entry(c, width=6); self.cd.insert(0, "5"); self.cd.pack(side="left", padx=6, pady=8)
        ttk.Label(c, text="min").pack(side="left")
        ttk.Button(c, text="Start", command=lambda: self.link.send("CD%d" % int(float(self.cd.get() or 0) * 60))).pack(side="left", padx=4)
        ttk.Button(c, text="Stop", command=lambda: self.link.send("CD0")).pack(side="left")
        for t, cmd in (("SW start", "SW1"), ("SW stop", "SW0"), ("SW reset", "SWR")):
            ttk.Button(c, text=t, command=lambda cmd=cmd: self.link.send(cmd)).pack(side="left", padx=4)
        mu = ttk.LabelFrame(f, text="Music (this PC)"); mu.pack(fill="x", padx=10, pady=8)
        for t, k in (("Prev", "prev"), ("Play / Pause", "pp"), ("Next", "next")):
            ttk.Button(mu, text=t, command=lambda k=k: media_key(k)).pack(side="left", padx=6, pady=8)
        ttk.Button(mu, text="Show music mode on buddy", command=lambda: self.link.send("MMUSIC")).pack(side="left", padx=10)
        ev = ttk.LabelFrame(f, text="Events / birthdays (MM-DD)"); ev.pack(fill="both", expand=True, padx=10, pady=8)
        self.evl = tk.Listbox(ev, height=5); self.evl.pack(side="left", fill="both", expand=True, padx=6, pady=6)
        bb = ttk.Frame(ev); bb.pack(side="left", padx=6)
        ttk.Button(bb, text="Add", command=self.add_event).pack(fill="x", pady=2)
        ttk.Button(bb, text="Delete", command=self.del_event).pack(fill="x", pady=2)
        ttk.Button(bb, text="Sync", command=self.sync_events).pack(fill="x", pady=2)
        self.draw_events()

    def _tab_settings(self):
        f = self.t_set
        r = ttk.LabelFrame(f, text="Identity"); r.pack(fill="x", padx=10, pady=8)
        self.e_user = ttk.Entry(r); self.e_dev = ttk.Entry(r)
        for i, (lab, e, cmd) in enumerate((("Your name", self.e_user, "SU"), ("Device name", self.e_dev, "SD"))):
            ttk.Label(r, text=lab).grid(row=i, column=0, padx=6, pady=4, sticky="w"); e.grid(row=i, column=1, sticky="ew", padx=6)
            ttk.Button(r, text="Save", command=lambda e=e, cmd=cmd: self.link.send(f"{cmd}|{e.get().strip()}")).grid(row=i, column=2, padx=6)
        r.columnconfigure(1, weight=1)
        w = ttk.LabelFrame(f, text="WiFi slots (4)"); w.pack(fill="x", padx=10, pady=8)
        self.wl = []
        for k in range(4):
            lab = ttk.Label(w, text=f"Slot {k + 1}: -", width=30); lab.grid(row=k, column=0, padx=6, pady=2, sticky="w"); self.wl.append(lab)
            ttk.Button(w, text="Set", command=lambda k=k: self.set_wifi(k)).grid(row=k, column=1, padx=4)
            ttk.Button(w, text="Remove", command=lambda k=k: self.link.send(f"WD|{k}")).grid(row=k, column=2, padx=4)
        g = ttk.LabelFrame(f, text="Gemini AI key"); g.pack(fill="x", padx=10, pady=8)
        self.e_key = ttk.Entry(g, show="*"); self.e_key.pack(side="left", fill="x", expand=True, padx=6, pady=8)
        ttk.Button(g, text="Save key", command=lambda: self.link.send("GK|" + self.e_key.get().strip())).pack(side="left", padx=6)
        x = ttk.LabelFrame(f, text="Device"); x.pack(fill="x", padx=10, pady=8)
        ttk.Button(x, text="Use this PC's time zone", command=self.set_tz).pack(side="left", padx=6, pady=8)
        ttk.Button(x, text="Restart", command=lambda: self.link.send("RB")).pack(side="left", padx=6)
        ttk.Button(x, text="Erase settings", command=self.erase).pack(side="left", padx=6)
        ttk.Button(x, text="Refresh info", command=lambda: self.link.send("I?")).pack(side="left", padx=6)

    # ------------- actions
    def say(self, t):
        self.log.config(state="normal"); self.log.insert("end", t + "\n"); self.log.see("end"); self.log.config(state="disabled")

    def refresh_ports(self):
        if serial is None: return
        ports = [f"{p.device}  -  {p.description}" for p in serial.tools.list_ports.comports()]
        self.port["values"] = ports
        if ports: self.port.current(0)

    def conn_usb(self):
        if serial is None: return messagebox.showerror("Missing", "pip install pyserial")
        if not self.port.get(): return messagebox.showinfo("USB", "No port selected. Plug the Desk Buddy in and press Refresh.")
        try:
            self.link.open_usb(self.port.get().split("  -  ")[0]); self.status.set("USB connected"); self.say("USB connected")
        except Exception as e:
            messagebox.showerror("USB", str(e))

    def scan_ble(self):
        if BleakClient is None: return messagebox.showerror("Missing", "pip install bleak")
        self.say("Scanning Bluetooth...")
        def run():
            try:
                devs = asyncio.run(BleakScanner.discover(timeout=6, return_adv=True))
                found = {}
                for addr, (d, adv) in devs.items():
                    n = d.name or adv.local_name or ""
                    if n.startswith("ARNO") or SVC.lower() in [u.lower() for u in adv.service_uuids]:
                        found[f"{n or 'ARNO'}  [{addr}]"] = addr
                self.ble_devs = found
                self.link.inbox.put("X|scan " + json.dumps(list(found.keys())))
            except Exception as e:
                self.link.inbox.put("X|error " + str(e))
        threading.Thread(target=run, daemon=True).start()

    def conn_ble(self):
        a = self.ble_devs.get(self.ble.get())
        if not a: return messagebox.showinfo("Bluetooth", "Press Scan, then pick ARNO-OS.")
        self.status.set("Connecting Bluetooth..."); self.link.open_ble(a)

    def disconnect(self):
        self.link.close(); self.status.set("Not connected"); self.say("Disconnected")

    def set_wifi(self, k):
        s = simpledialog.askstring("WiFi", "Network name (SSID):", parent=self)
        if not s: return
        p = simpledialog.askstring("WiFi", "Password:", show="*", parent=self) or ""
        self.link.send(f"WS|{k}|{s.strip()}|{p}")

    def set_tz(self):
        off = -(time.altzone if time.localtime().tm_isdst and time.daylight else time.timezone) // 60
        self.link.send(f"TZ|{off}")

    def erase(self):
        if messagebox.askyesno("Erase", "Erase name, WiFi and keys on the Desk Buddy? (firmware stays)"): self.link.send("ERASE")

    def draw_events(self):
        self.evl.delete(0, "end")
        for d, t in self.events: self.evl.insert("end", f"{d}   {t}")

    def add_event(self):
        d = simpledialog.askstring("Event", "Date as MM-DD (e.g. 07-15):", parent=self)
        if not d or len(d) != 5 or d[2] != "-": return messagebox.showinfo("Event", "Use MM-DD, e.g. 07-15")
        t = simpledialog.askstring("Event", "Title (e.g. Arnod Birthday):", parent=self)
        if not t: return
        self.events.append((d, t.replace("|", " ")[:28])); self.events.sort(); self.save_cfg(); self.draw_events(); self.sync_events()

    def del_event(self):
        s = self.evl.curselection()
        if s: del self.events[s[0]]; self.save_cfg(); self.draw_events(); self.sync_events()

    def sync_events(self):
        self.link.send("EV|CLR")
        for d, t in self.events: self.link.send(f"EV|ADD|{d}|{t}")

    def save_cfg(self):
        self.cfg["events"] = self.events
        try: json.dump(self.cfg, open(CFG, "w"))
        except Exception: pass

    # ------------- incoming
    def _poll(self):
        try:
            while True:
                l = self.link.inbox.get_nowait()
                p = l.split("|")
                if p[0] == "X":
                    msg = l[2:]
                    if msg.startswith("scan "):
                        names = json.loads(msg[5:]); self.ble["values"] = names
                        if names: self.ble.current(0)
                        self.say(f"Found {len(names)} Desk Buddy" if names else "No Desk Buddy found - is it on and not connected to the phone?")
                    elif msg == "ble-connected": self.status.set("Bluetooth connected"); self.say("Bluetooth connected")
                    elif msg == "lost": self.status.set("Connection lost")
                    else: self.say(msg)
                elif p[0] == "I" and len(p) >= 3:
                    self.info[p[1]] = "|".join(p[2:])
                    if p[1] == "user" and not self.e_user.get(): self.e_user.insert(0, self.info["user"])
                    if p[1] == "dev" and not self.e_dev.get(): self.e_dev.insert(0, self.info["dev"])
                    if p[1].startswith("w") and p[1][1:].isdigit(): self.wl[int(p[1][1:])].config(text=f"Slot {int(p[1][1:]) + 1}: {self.info[p[1]]}")
                    if p[1] == "end":
                        self.status.set(f"{self.link.mode.upper() if self.link.mode else ''} - {self.info.get('dev','')} - {self.info.get('os','')} - WiFi: {self.info.get('wifi','')}")
                elif p[0] == "C" and len(p) > 1 and p[1] == "PP": media_key("pp")
                elif p[0] == "S" and len(p) > 1 and p[1] == "cd": messagebox.showinfo("Desk Buddy", "Timer completed!")
                elif p[0] in ("G", "M"): self.say("Desk Buddy: " + "|".join(p[1:]))
        except queue.Empty:
            pass
        self.after(100, self._poll)


if __name__ == "__main__":
    App().mainloop()
