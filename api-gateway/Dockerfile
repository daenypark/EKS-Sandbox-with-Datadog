FROM krakend:2.10.2
# KrakenD 설정 파일 복사
COPY krakend.json /etc/krakend/krakend.json

# 포트 노출
EXPOSE 8080

# KrakenD 실행
CMD ["krakend", "run", "-c", "/etc/krakend/krakend.json"]
