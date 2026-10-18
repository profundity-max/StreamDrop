#!/usr/bin/env python3
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import time, sys, os
DATA = bytes(range(256)) * 16384
MEDIA = os.environ.get('STREAMDROP_FIXTURE_MEDIA','/tmp/streamdrop-fixture.mp4')
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_HEAD(self): self.respond(False)
    def do_GET(self): self.respond(True)
    def respond(self, body):
        path=self.path.split('?')[0]
        if path=='/missing.mp4':
            self.send_error(404); return
        if path=='/page':
            data=b'<html><head><title>Local media fixture</title></head><body><video controls src="/sample.mp4"></video></body></html>'
            self.send_response(200); self.send_header('Content-Type','text/html'); self.send_header('Content-Length',str(len(data))); self.end_headers()
            if body:self.wfile.write(data)
            return
        if path=='/html.mp4':
            data=b'<html>Not a video</html>'; content='text/html'
        elif path=='/vp9.mp4' and os.path.exists(os.environ.get('STREAMDROP_FIXTURE_VP9','/nonexistent')):
            data=open(os.environ['STREAMDROP_FIXTURE_VP9'],'rb').read();content='video/mp4'
        elif path=='/sample.mp4' and os.path.exists(MEDIA):
            data=open(MEDIA,'rb').read();content='video/mp4'
        else:data=DATA;content='application/octet-stream'
        start=0
        if self.headers.get('Range','').startswith('bytes='):
            start=int(self.headers['Range'].split('=')[1].split('-')[0])
        self.send_response(206 if start else 200)
        self.send_header('Content-Type',content)
        self.send_header('Accept-Ranges','bytes')
        self.send_header('ETag','"streamdrop-fixture-v1"')
        self.send_header('Last-Modified','Sun, 18 Oct 2026 00:00:00 GMT')
        if start:self.send_header('Content-Range',f'bytes {start}-{len(data)-1}/{len(data)}')
        self.send_header('Content-Length',str(len(data)-start));self.end_headers()
        if body:
            try:
                for i in range(start,len(data),32768):
                    self.wfile.write(data[i:i+32768]); self.wfile.flush()
                    if path.startswith('/slow'):time.sleep(.03)
            except (BrokenPipeError,ConnectionResetError):pass
server=ThreadingHTTPServer(('127.0.0.1',18764),Handler)
print('fixture listening on http://127.0.0.1:18764',flush=True)
server.serve_forever()
