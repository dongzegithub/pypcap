#
# pcap.pyx
#
# $Id$

"""packet capture library

This module provides a high level interface to packet capture systems.
All packets on the network, even those destined for other hosts, are
accessible through this mechanism.
"""

__author__ = 'Dug Song <dugsong@monkey.org>'
__copyright__ = 'Copyright (c) 2004 Dug Song'
__license__ = 'Python'
__url__ = 'http://monkey.org/~dugsong/pypcap/'
__version__ = '0.2'

import sys

cdef extern from "Python.h":
    object PyString_FromStringAndSize(char *s, int len)
    void  *PyList_New(int n)
    void  *PyMem_Malloc(int n)
    void   PyMem_Free(void *)
    int	   Py_BEGIN_ALLOW_THREADS	# XXX
    int    Py_END_ALLOW_THREADS		# XXX
    object PyErr_SetFromErrno(object type)
    
cdef extern from "pcap-int.h":
    # XXX - to make pcap_fileno() work with dumpfiles...
    cdef struct pcap_sf:
        void   *rfile			# XXX
    ctypedef struct pcap_t:
        int     fd
        pcap_sf sf
    
cdef extern from "pcap.h":
    cdef struct bpf_program:
        int __xxx
    cdef struct bpf_timeval:
        unsigned int tv_sec
        unsigned int tv_usec
    cdef struct pcap_stat:
        unsigned int ps_recv
        unsigned int ps_drop
        unsigned int ps_ifdrop
    cdef struct pcap_pkthdr:
        bpf_timeval ts
        unsigned int caplen
    
    ctypedef void (*pcap_handler)(void *arg, pcap_pkthdr *hdr, char *pkt)
    
    pcap_t *pcap_open_live(char *device, int snaplen, int promisc,
                           int to_ms, char *errbuf)
    pcap_t *pcap_open_offline(char *fname, char *errbuf)
    char   *pcap_lookupdev(char *errbuf)
    int     pcap_compile(pcap_t *p, bpf_program *fp, char *str, int optimize,
                         unsigned int netmask)
    int     pcap_setfilter(pcap_t *p, bpf_program *fp)
    int     pcap_dispatch(pcap_t *p, int cnt, pcap_handler callback,
                          unsigned char *arg)
    unsigned char *pcap_next(pcap_t *p, pcap_pkthdr *hdr)
    int     pcap_datalink(pcap_t *p)
    int     pcap_snapshot(pcap_t *p)
    int     pcap_stats(pcap_t *p, pcap_stat *ps)
    int     pcap_fileno(pcap_t *p)
    char   *pcap_geterr(pcap_t *p)
    void    pcap_close(pcap_t *p)

cdef extern from "setjmp.h":
    ctypedef struct jmp_buf:
        int __xxx
    int  setjmp(jmp_buf env)
    void longjmp(jmp_buf env, int val)

cdef extern from *:
    int   R_OK
    int   access(char *path, int mode)
    char *strdup(char *src)
    void  free(void *ptr)
    int   fileno(void *f)		# XXX
    
    ctypedef struct fd_set:
        int __xxx
    void FD_ZERO(fd_set *fdset)
    void FD_SET(int fd, fd_set *fdset)
    int  FD_ISSET(int fd, fd_set *fdset)
    int  select(int nfds, fd_set *rfds, fd_set *wfds, fd_set *efds, void *tv)

cdef struct pcap_handler_ctx:
    void   *callback
    void   *arg
    void   *exc
    jmp_buf env

cdef void __pcap_handler(void *arg, pcap_pkthdr *hdr, char *pkt):
    cdef pcap_handler_ctx *ctx
    ctx = <pcap_handler_ctx *>arg
    try:
        (<object>ctx.callback)(hdr.ts.tv_sec + (hdr.ts.tv_usec / 1000000.0),
                               PyString_FromStringAndSize(pkt, hdr.caplen),
                               <object>ctx.arg)
    except:
        # XXX - don't interfere with Pyrex internal exception handling
        (<object>ctx.exc).extend(sys.exc_info())
        longjmp(ctx.env, 1)

DLT_NULL =	0
DLT_EN10MB =	1
DLT_EN3MB =	2
DLT_AX25 =	3
DLT_PRONET =	4
DLT_CHAOS =	5
DLT_IEEE802 =	6
DLT_ARCNET =	7
DLT_SLIP =	8
DLT_PPP =	9
DLT_FDDI =	10

# XXX - OpenBSD
DLT_PFLOG =	117
DLT_PFSYNC =	18
if 'openbsd' in sys.platform:
    DLT_LOOP =		12
    DLT_RAW =		14
else:
    DLT_LOOP =		108
    DLT_RAW =		12

dloff = { DLT_NULL:4, DLT_EN10MB:14, DLT_IEEE802:22, DLT_ARCNET:6,
          DLT_SLIP:16, DLT_PPP:4, DLT_FDDI:21, DLT_PFLOG:48, DLT_PFSYNC:4,
          DLT_LOOP:4, DLT_RAW:0 }

cdef class pcap:
    """pcap(name=None, snaplen=65535, promisc=True) -> packet capture object
    
    Open a handle to a packet capture descriptor.
    
    Keyword arguments:
    name    -- name of a network interface or dumpfile to open,
               or None to open the first available up interface.
    snaplen -- maximum number of bytes to capture for each packet
    promisc -- boolean to specify promiscuous mode sniffing
    """
    cdef pcap_t *__pcap
    cdef char *__name
    cdef char *__filter
    cdef char __ebuf[128]
    cdef int __dloff
    
    def __init__(self, name=None, snaplen=65535, promisc=True,
                 immediate=False):
        global dloff
        cdef char *p
        
        if not name:
            p = pcap_lookupdev(self.__ebuf)
            if p == NULL:
                raise OSError, "couldn't lookup device"
            self.__name = strdup(p)
        else:
            self.__name = strdup(name)
            
        self.__filter = strdup("")
        
        if access(self.__name, R_OK) == 0:
            self.__pcap = pcap_open_offline(self.__name, self.__ebuf)
            # XXX - libpcap should do this!
            if self.__pcap:
                self.__pcap.fd = fileno(self.__pcap.sf.rfile)
        else:
            self.__pcap = pcap_open_live(self.__name, snaplen, promisc, 50,
                                         self.__ebuf)
        if not self.__pcap:
            raise OSError, self.__ebuf

        try: self.__dloff = dloff[pcap_datalink(self.__pcap)]
        except KeyError: pass
    
    property name:
        """Network interface or dumpfile name."""
        def __get__(self):
            return self.__name

    property snaplen:
        """Maximum number of bytes to capture for each packet."""
        def __get__(self):
            return pcap_snapshot(self.__pcap)
        
    property dloff:
        """Datalink offset (length of layer-2 frame header)."""
        def __get__(self):
            return self.__dloff
    
    property fd:
        """File descriptor for capture handle."""
        def __get__(self):
            return pcap_fileno(self.__pcap)

    property filter:
        """Current packet capture filter."""
        def __get__(self):
            return self.__filter
    
    def fileno(self):
        """Return file descriptor for capture handle."""
        return pcap_fileno(self.__pcap)
    
    def setfilter(self, value):
        """Set BPF-format packet capture filter."""
        cdef bpf_program fcode
        free(self.__filter)
        self.__filter = strdup(value)
        if pcap_compile(self.__pcap, &fcode, self.__filter, 1, 0) < 0:
            raise OSError, pcap_geterr(self.__pcap)
        if pcap_setfilter(self.__pcap, &fcode) < 0:
            raise OSError, pcap_geterr(self.__pcap)
    
    def datalink(self):
        """Return datalink type (DLT_* values)."""
        return pcap_datalink(self.__pcap)
    
    def next(self):
        """Return the next (timestamp, packet) tuple, or None on error."""
        cdef pcap_pkthdr hdr
        cdef char *pkt
        pkt = <char *>pcap_next(self.__pcap, &hdr)
        if not pkt:
            return None
        return (hdr.ts.tv_sec + (hdr.ts.tv_usec / 1000000.0),
                PyString_FromStringAndSize(pkt, hdr.caplen))

    def __add_pkts(self, ts, pkt, pkts):
        pkts.append((ts, pkt))
    
    def readpkts(self):
        """Return a list of (timestamp, packet) tuples received in one buffer."""
        pkts = []
        self.dispatch(self.__add_pkts, pkts)
        return pkts
    
    def dispatch(self, callback, arg=None, cnt=-1):
        """Collect and process packets with a user callback,
        return the number of packets processed.
        
        Arguments:
        
        callback -- function with (timestamp, pkt, arg) prototype
        arg      -- optional argument passed to callback on execution
        cnt      -- number of packets to process;
                    or 0 to process all packets until an error occurs,
                    EOF is reached, or the read times out;
                    or -1 to process all packets received in one buffer
        """
        cdef pcap_handler_ctx *ctx
        cdef int n

        # XXX - because Pyrex doesn't understand 'volatile'
        ctx = <pcap_handler_ctx *>PyMem_Malloc(sizeof(pcap_handler_ctx))
        ctx.callback = <void *>callback
        ctx.arg = <void *>arg
        ctx.exc = PyList_New(0)	# XXX
        
        if setjmp(ctx.env) == 0:
            n = pcap_dispatch(self.__pcap, cnt, __pcap_handler,
                              <unsigned char *>ctx)
            PyMem_Free(ctx)
            if n < 0:
                raise OSError, pcap_geterr(self.__pcap)
            return n
        
        exc = <object>ctx.exc
        PyMem_Free(ctx)
        raise exc[0], exc[1], exc[2]

    def loop(self, callback, arg=None):
        """Loop forever, processing packets with a user callback.
        The loop can be exited with an exception, including KeyboardInterrupt.
        
        Arguments:

        callback -- function with (timestamp, pkt, arg) prototype
        arg      -- optional argument passed to callback on execution
        """
        cdef fd_set rfds
        cdef int fd, n
        
        fd = pcap_fileno(self.__pcap)
        if fd < 0:
            raise OSError, pcap_geterr(self.__pcap)
        while 1:
            FD_ZERO(&rfds)
            FD_SET(fd, &rfds)
            Py_BEGIN_ALLOW_THREADS
            n = select(fd + 1, &rfds, NULL, NULL, NULL)
            Py_END_ALLOW_THREADS
            if n <= 0:
                PyErr_SetFromErrno(OSError)
            elif FD_ISSET(fd, &rfds) != 0:
                if self.dispatch(callback, arg) == 0:
                    break
    
    def geterr(self):
        """Return the last error message associated with this handle."""
        return pcap_geterr(self.__pcap)
    
    def stats(self):
        """Return a 3-tuple of the total number of packets received,
        dropped, and dropped by the interface."""
        cdef pcap_stat pstat
        if pcap_stats(self.__pcap, &pstat) < 0:
            raise OSError, pcap_geterr(self.__pcap)
        return (pstat.ps_recv, pstat.ps_drop, pstat.ps_ifdrop)
    
    def __dealloc__(self):
        if self.__name:
            free(self.__name)
        if self.__filter:
            free(self.__filter)
        if self.__pcap:
            pcap_close(self.__pcap)
    
def lookupdev():
    """Return the name of a network device suitable for sniffing."""
    cdef char *p, buf[128]
    p = pcap_lookupdev(buf)
    if p == NULL:
        raise OSError, buf
    return p
