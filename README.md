# 엣지 컴퓨팅 환경에서 CPU 스케줄링이 네트워크 성능에 미치는 영향 분석
## 실험 환경

* 엣지 장치로 raspberry pi 와 jetson orin nano 를 선책하여 이를 비교 관찰 하였음
* 서버 환경
  * Intel(R) Core(TM) i7-10700K CPU 16코어 @ 3.80GHz와 64 GB 메모리 탑재
  * Linux version : Ubuntu 22.04.3 LTS, kernel version : 5.15.0-91-generic
* 엣지 환경
  * raspberry pi
    * Broadcom BCM2711, quad-core Cortex-A72 (ARM v8) 64-bit SoC @ 1.5GHz 와 8 GB 메모리 탑재
    * Linux version : Ubuntu 22.04.3 LTS, kernel version : 5.15.0-1045-raspi
  * jetson orin nano
    * 6-core Arm® Cortex®-A78AE v8.2 64-bit CPU, 1024-core NVIDIA Ampere architecture GPU with 32 Tensor Cores, 8 GB 메모지 탑재
    * Linux version : Ubuntu 20.04.6 LTS, kernel version : 5.10.120-tegra
---
## 실험 방법 및 목적
* 엣지 장치에서 네트워크 트래픽을 처리할때 트래픽을 구성하는 메세지의 크기에 따라 초당 처리하는 패킷 수와 소모되는 CPU 사용량이 달라지기 때문에 네트워크 성능 또한 달라 질 수 있음
* 본 실험에서는 메세지 크기를 64B 에서 1024B로 증가시켰을때 네트워크 성능을 5회 반복하여 측정하며 측정시 마다 성능 편차가 발생한 경우 그 원인을 파악하기 위해 netperf 프로세스가 동작하는 CPU 코어를 서로 다른 코어로 변경하면서 고정하였을 때 그 영향을 관찰함
* rasberry pi 와 jetson orin nano 에서 각각 pod 를 생성하여 pod 에서 server로 netperf 를 실행 한 후 pod 의 네트워크 처리량 관찰
---
## 데이터 수집을 위한 환경 세팅
* kubernete cluster 환경 구성 ( gpu server - master, ubuntu server - worker, orin server - worker )
* gpu server(master) 에서 netserver 실행
    * netserver
    * 그냥 실행 시 default 로 port 12865 지정
* pod 생성
    * ubuntu 실험 시 ubuntu에 pod 생성, orin 실험 시 orin에 pod 생성
    * image : jjong2/all:latest 에는 데이터 수집에 필요한 netperf, vnstat, sysstat 등 툴이 설치되어 있는 이미지 파일
    * resource: lmits: cpu: 는 pod 의 cpu 를 지정해주는 것, 실험에서는 1000m (1코어)로 설정하여 실행
    * nodeSelector : key 를 통하여 orin, ubuntu 에 지정하여 pod 생성
```sh
kind: Pod
apiVersion: v1
metadata:
  name: p1
spec:
  containers:
    - name: p1
      image: jjong2/all:latest
      command: ["/bin/bash", "-ec", "while :; do echo '.'; sleep 5 ; done"]
      resources:
        limits:
         cpu: 1000m # 10m, 20m, ... 1000m
  #nodeSelector:
    # key: orin, ubuntu
  restartPolicy: Never
```
---
## 데이터 수집
* ubuntu, orin server 에서 netperf 실행
* 실험 스크립트
  * collect_data.sh
```sh
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
```
* 위에 보이는 코드는 ubuntu에 대하여 실행 할 때의 코드이므로 orin에서 돌린다면 ubuntu 에 해당하는 내용만 orin 내용으로 바꿔주면 됨 (ip, pod 등)
* message size 를 64B 에서 1024B 까지 2배씩 커지면서 netperf를 실행
* 10초간 12번 총 120초 동안의 데이터 수집 후 message size 2배 증가
* vnstat은 네트워크 트래픽 모니터링 툴로써 throughput 과 pps 측정
* pidstat은 특정 pid에 대한 cpu 사용량 모니터링 툴로써 netperf 의 cpu 사용량을 측정
* mpstat은 리눅스 서버의 cpu 코어 별 사용량 모니터링 툴로써 netperf 가 실행될 때 사용되는 core 별 cpu 사용량을 측정
* 정확한 측정을 위하여 netperf 를 실행 한 후 측정이 끝나면 netperf 를 종료한 후 다시 netperf 를 실행하였다 ( netperf가 여러 process에서 실행되는걸 방지 )






