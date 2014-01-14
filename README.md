
eNose
======

## Changes

0.01: Initial version
0.02: Initial working version of stream parser

## features:

- epcap_app:
+ traces the incoming IP packages coming from pcap
+ Currently supports only for TCP traffic (UDP is ignored)
+ Only for IP4 checksum filtering has been done.
+ IP6 has no support for checksum verification yet and has not been intensively been tested. It should work, if there are no bit errors in the IP4 packages.
+ Preferably deactivate IP6 traffic for now.
+ dropps IP4 packages with invalid TCP or IP4 checksum
+ Packets from epcap_app to be forwarded to the stream_app or directly to the content app

- stream_app:
+ tracks sequence numbers and Acks
+ handles retransmission of TCP packages
+ collects pieces of 1500 bytes to be forwarded to the content_app

- content_app:
+ this is the content filtering
+ Decent search performance is only achieved by using erlang binary search. See example s12:s() for network interfaces e.g. "eth0" or s12:s() for "eth1".

## Preconditions

   This tool checks the checksum of the received packages. In todays PCs the network card generates the checksums,
   long time after the package has been captured by pcap. In order to avoid ignoring those packages due to failed
   checksums it is important to deactivate tcp checksum offloading.

   Therefore before using the this program, check that all tcp checksum offloading had been deactivated.

   su 
   ethtool --show-offload eth0
   E.g.:
   > 
   > generic-receive-offload: on
   >

   If e.g. generic-receive-offloading is activated, deactiavte it using the following command:

   ethtool -K eth0 gro off

   Similarly apply this to all other activated offloading features.
   Note: 

   This has to be repeated after server start.
   See also: https://github.com/msantos/pkt/issues/9

   For Ubuntu 13.10 the following apply:

   sudo ethtool -K eth0 rx off tx off tso off sg off gro off

   Note:
   Deactivation of checksum offloading is currently broken on Debian stable (Whezzy) and Debian testing (Jessie).
   See my bug report for Debian stable:
   http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=735196

## QUICK SETUP

    cd eNose

    make all

    # if dependencies are not intalled automatically run the following and repeat the step above 
    # (please report back if it does not work without):
    ./rebar get-deps

        
    # Allow your user to epcap with root privs
    sudo visudo
    youruser ALL = NOPASSWD: /path/to/eNose/deps/epcap/priv/epcap
    
    In case you run into the error message: "sudo: sorry, you must have a tty to run sudo", see:
    https://github.com/msantos/epcap/issues/15

    run:
    ./start.sh eth0
    
    Have a look in the file examples/s12.erl, which is started from "./start.sh"
    - Edit here the multi-search pattern. Currently it is checked for:
    <<"meldung">> or <<"thema">> or <<"Ubuntu">> or the hex string<<16#0b, 16#07, 16#69, 16#72, 16#8b, 16#00, 16#d0, 16#28, 16#a9, 16#4b>>.
    
    instead running it from network card, you may run it also using a pcap trace file:

    ./start_from_file.sh "/path/my_pcap_trace.pcap"
    
    
    Note:
    - after changing the search pattern, "make all" must be called
    - Erlang must be restrated.

    On shell 1:

    cd eNose
    make all

    (should compile everything, including
    ./rebar get-deps (if downloading of dependencies had failed)


    ./start.sh (starts erlang shell with right coockie and path)

    In Erlang shall:
    s12_1:s().



    On shell 2:
    cd eNose

    run:
    ./observer.sh (starts the observer)
    In the observer select Nodes -> eNose...
 

## USAGE

    This applies to the files called by ./start.sh, ./start_from_file.sh located in the example directory:

    {ok, Roleback} = rule:start([{AppName1,[{key1, value1}, {key2, value2}, ...]}, {AppName2,[{key1, value1}, {key2, value2}, ...]}, ..., {AppNameN,[{key1, value1}, {key2, value2}]}).

    
    1) epcap_port:
        directoy: epcap_port_app 
        
        Types   Args = [Options]
                Options = {chroot, string()} | {group, string()} | {interface, string()} | {promiscuous, boolean()} |
                            {user, string()} | {filter, string()} | {progname, string()} | {file, string()} |
                            {monitor, boolean() | {cpu_affinity, string()} | {cluster_id, non_neg_integer()}}

    2) stream: 
        Collects the incoming tcp stream payload into packages of 1500 bytes. Tracks sequence numbers and acknowleges. 
        Forwards the received content e.g. towards the configured "content"-app. 


    3) content:
        It filters content received from epcap_port or from defrag based upon strings and prints the results.

## PF_RING -- currently not tested ----
        This section refers to epcap, not to the epcap_port app and is automatically downloaded 
        by rebar and found here: "eNose/deps/epcap"
        In case you want to compile epcap with PF_RING support,
        just specify the path to the libpfring and modified libpcap libraries
        via shell variable PFRING.

            PFRING=/home/user/pfring make

        As a result epcap binary will be linked with the following flags: -static -lpfring -lpthread

        To complete the configuration you need to set up the cluster_id option.
        The value of the cluster_id option is integer and should be in range between 0 and 255.
        
        
            epcap:start([{interface, "lo"}, {cluster_id, 2}]).

	E.g. 
	rule:start([{epcap_port,[{interface, "lo"}, {cluster_id, 2}, {filter, "icmp or (tcp and port 80)"}]}, {content, [{matchfun, NeverMatchFun}]}, {message, "This should never ocurr!!!"}])
        You can also specify the option cpu_affinity to set up CPU affinity for epcap port:

            epcap:start([{interface, "lo"}, {cluster_id, 2}, {cpu_affinity, "1,3,5-7"}]).
	E.g. 
	rule:start([{epcap_port,[{interface, "lo"}, {cluster_id, 2}, {cpu_affinity, "1,3,5-7"}, {filter, "icmp or (tcp and port 80)"}]}, {content, [{matchfun, NeverMatchFun}]}, {message, "This should never ocurr!!!"}])
	

## SCREENSHOT

tbd.

## TODO

* make it distributed application
* add futher applications

## Interesting Books:

Erlang and OTP in Action, Martin Logan, Eric Merritt, Richard Carlsson / for Erlang OTP

For intrusion detection:
Snort 2.0 Intrusion Detectionby Brian Caswell, Jeffrey Pusluns and Jay Beale from Syngress Media (May 1st 2003) 


## CONTRIBUTORS

This project would not be possible without the great work on epcap:

https://github.com/msantos/epcap

