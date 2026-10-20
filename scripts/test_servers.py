"""Readiness and failure ownership for the loopback test servers."""
import socket, time

def wait_for_servers(servers,ports,timeout=30):
    started=time.monotonic()
    for port in ports:
        while True:
            for server in servers:
                if server.poll() is not None:
                    raise RuntimeError(f'Fixture process {server.pid} exited with {server.returncode}; see .test-output/servers.log')
            try:
                with socket.create_connection(('127.0.0.1',port),timeout=.2):break
            except OSError:
                if time.monotonic()-started>timeout:raise RuntimeError(f'Server {port} not ready after {timeout}s; see .test-output/servers.log')
                time.sleep(.05)
        print(f'Fixture {port} ready after {time.monotonic()-started:.2f}s',flush=True)
