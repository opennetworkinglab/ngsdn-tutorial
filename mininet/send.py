#!/usr/bin/python

# Script used in Exercise 8.
# Send downlink packets to UE address.

from scapy.layers.inet import IP, UDP
from scapy.sendrecv import send

UE_ADDR = '17.0.0.1'
RATE = 5  # packets per second
PAYLOAD = ' '.join(['P4 is great!'] * 50)

print "Sending %d UDP packets per second to %s..." % (RATE, UE_ADDR)

pkt = IP(dst=UE_ADDR) / UDP(sport=80, dport=400) / PAYLOAD
send(pkt, inter=1.0 / RATE, loop=True, verbose=True)
