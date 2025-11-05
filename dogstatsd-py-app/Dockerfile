FROM python:3
WORKDIR /usr/src/app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
RUN pip install ddtrace
RUN pip install --upgrade pip
RUN pip install datadog
COPY app.py ./app.py
CMD ["ddtrace-run", "python", "app.py"]
