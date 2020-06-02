#!/usr/bin/python

# Script used in Exercise 8 that sniffs packets and prints on screen whether
# they are GTP encapsulated or not.

import signal
import sys

from ptf.packet import IP
from scapy.contrib import gtp
from scapy.sendrecv import sniff

pkt_count = 0


def handle_pkt(pkt, ex):
    global pkt_count
    pkt_count = pkt_count + 1
    if gtp.GTP_U_Header in pkt:
        is_gtp_encap = True
    else:
        is_gtp_encap = False

    print "[%d] %d bytes: %s -> %s, is_gtp_encap=%s\n\t%s" \
          % (pkt_count, len(pkt), pkt[IP].src, pkt[IP].dst,
             is_gtp_encap, pkt.summary())

    if is_gtp_encap and ex:
        exit()


print "Will print a line for each UDP packet received..."


def handle_timeout(signum, frame):
    print "Timeout! Did not receive any GTP packet"
    exit(1)


exitOnSuccess = False
if len(sys.argv) > 1 and sys.argv[1] == "-e":
    # wait max 10 seconds or exit
    signal.signal(signal.SIGALRM, handle_timeout)
    signal.alarm(10)
    exitOnSuccess = True

sniff(count=0, store=False, filter="udp",
      prn=lambda x: handle_pkt(x, exitOnSuccess))
