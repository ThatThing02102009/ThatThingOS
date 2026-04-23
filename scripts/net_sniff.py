#!/usr/bin/env python3
"""
net_sniff.py — ThatThingOS network sniff + packet analysis scaffold
Requires: scapy (pip install scapy) and root
Usage: sudo python3 net_sniff.py [-i iface] [-f filter] [-c count]
"""
import argparse
import sys
import signal
from datetime import datetime

try:
    from scapy.all import (
        sniff, IP, TCP, UDP, ICMP, DNS, DNSQR, DNSRR,
        ARP, Ether, Raw, hexdump, wrpcap
    )
except ImportError:
    sys.exit("[!] scapy not found: pip install scapy")

# ── Terminal colours ───────────────────────────────────────────────────
C  = "\033[36m"   # cyan
Y  = "\033[33m"   # yellow
R  = "\033[31m"   # red
G  = "\033[32m"   # green
M  = "\033[35m"   # magenta
W  = "\033[0m"    # reset
B  = "\033[1m"    # bold

BANNER = f"""
{C}{B}╔══════════════════════════════════════════╗
║   ThatThingOS // NET_SNIFF v1.0          ║
║   passive capture + protocol decode      ║
╚══════════════════════════════════════════╝{W}
"""

captured = []

def decode_packet(pkt):
    ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]

    # ── ARP ────────────────────────────────────────────────────────────
    if pkt.haslayer(ARP):
        arp = pkt[ARP]
        op = "WHO-HAS" if arp.op == 1 else "IS-AT"
        print(f"{Y}[{ts}] ARP {op}  {arp.psrc} ({arp.hwsrc}) → {arp.pdst}{W}")
        return

    if not pkt.haslayer(IP):
        return

    ip = pkt[IP]
    src, dst = ip.src, ip.dst

    # ── DNS ────────────────────────────────────────────────────────────
    if pkt.haslayer(DNS):
        dns = pkt[DNS]
        if dns.qr == 0 and dns.qd:
            name = dns.qd.qname.decode(errors="replace").rstrip(".")
            print(f"{C}[{ts}] DNS Q  {src} → {name}{W}")
        elif dns.qr == 1 and dns.an:
            name = dns.an.rrname.decode(errors="replace").rstrip(".")
            resp = dns.an.rdata if hasattr(dns.an, "rdata") else "?"
            print(f"{G}[{ts}] DNS A  {name} → {resp}{W}")
        return

    # ── TCP ────────────────────────────────────────────────────────────
    if pkt.haslayer(TCP):
        tcp = pkt[TCP]
        flags = tcp.sprintf("%TCP.flags%")
        sport, dport = tcp.sport, tcp.dport
        payload_len = len(tcp.payload)
        line = f"{W}[{ts}] TCP {src}:{sport} → {dst}:{dport}  [{flags}]"

        # Flag interesting ports
        interesting = {80, 443, 8080, 8443, 25, 587, 21, 22, 3306, 5432, 27017}
        if dport in interesting or sport in interesting:
            line = f"{M}{B}" + line
        else:
            line = f"{W}" + line

        if payload_len > 0:
            line += f"  {payload_len}B"
            if pkt.haslayer(Raw):
                raw = bytes(pkt[Raw])[:80]
                printable = raw.decode("latin-1", errors="replace")
                if any(k in printable.lower() for k in ["user", "pass", "token", "auth", "bearer"]):
                    line += f"\n  {R}{B}↳ CRED? {printable!r}{W}"

        print(line + W)
        return

    # ── UDP ────────────────────────────────────────────────────────────
    if pkt.haslayer(UDP):
        udp = pkt[UDP]
        print(f"{W}[{ts}] UDP {src}:{udp.sport} → {dst}:{udp.dport}  {len(udp.payload)}B{W}")
        return

    # ── ICMP ───────────────────────────────────────────────────────────
    if pkt.haslayer(ICMP):
        icmp = pkt[ICMP]
        print(f"{Y}[{ts}] ICMP type={icmp.type} {src} → {dst}{W}")


def on_packet(pkt):
    captured.append(pkt)
    try:
        decode_packet(pkt)
    except Exception as e:
        print(f"{R}[!] decode error: {e}{W}")


def main():
    parser = argparse.ArgumentParser(description="ThatThingOS net_sniff")
    parser.add_argument("-i", "--iface",  default=None,      help="Interface (default: all)")
    parser.add_argument("-f", "--filter", default="",        help="BPF filter")
    parser.add_argument("-c", "--count",  default=0,  type=int, help="Packet count (0=∞)")
    parser.add_argument("-o", "--out",    default=None,      help="Write PCAP to file")
    args = parser.parse_args()

    print(BANNER)
    print(f"{B}Interface: {args.iface or 'any'}  |  Filter: '{args.filter or 'none'}'{W}\n")

    def sigint(sig, frame):
        print(f"\n{Y}[*] Captured {len(captured)} packets.{W}")
        if args.out and captured:
            wrpcap(args.out, captured)
            print(f"{G}[+] Saved to {args.out}{W}")
        sys.exit(0)

    signal.signal(signal.SIGINT, sigint)

    sniff(
        iface=args.iface,
        filter=args.filter,
        count=args.count,
        prn=on_packet,
        store=False,
    )


if __name__ == "__main__":
    main()
