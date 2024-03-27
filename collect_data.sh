#!/bin/bash

pkt=64
for j in $(seq 1 5)
do
    mkdir $1/p${pkt}
    echo $pkt
    # Start Netperf
    kubectl exec -it p1 --namespace=default -- netperf -H 192.168.0.3 -p 12865 -l 500 -- -m "${pkt}" &

    # Wait for netperf to start
    sleep 5

    # Collect Data 12times
    for k in $(seq 1 12)
    do
        # Collect data
        kubectl exec -it p1 --namespace=default -- vnstat -tr 10 |awk '/tx/' |awk '{print $2, $4}' >> $1/p${pkt}/vnstat.txt&
        sshpass -p ???? ssh -o StrictHostKeyChecking=no ubuntu2@155.230.16.157 -p 40003 "pidstat -G netperf 1 10" |awk '/Average/'|awk '/netperf/'|awk '{ print $8 }'  >> $1/p${pkt}/pidstat_netperf.txt&
        kubectl exec -it p1 --namespace=default -- mpstat -P ALL 10 1 >> $1/p${pkt}/mpstat.txt
        # Wait before collecting the next set of data 
        sleep 3
    done

    # pkt * 2
    ((pkt=${pkt}*2))

    # Stop netperf
    sshpass -p ???? ssh -o StrictHostKeyChecking=no ubuntu2@155.230.16.157 -p 40003 sudo killall netperf

    sleep 1
    # Increment packet size
done
