from datadog import initialize, statsd
from ddtrace import tracer
import time
import os

# Initialize DogStatsD
options = {
    "statsd_socket_path": "/var/run/datadog/dsd.socket"
}
initialize(**options)

print("Starting app with tracing...")

while True:
    # Generate a simple trace
    with tracer.trace("simple.operation", service="dogstatsd-python-app") as span:
        span.set_tag("environment", "fargate")
        
        # Send metrics
        statsd.increment('containerspod.isthebest', tags=["environment:lowkey"])
        statsd.decrement('failedatdoing.ecsfargatelogging', tags=["environment:sad"])
        
        print("Sent metrics and generated trace")
        time.sleep(10)
