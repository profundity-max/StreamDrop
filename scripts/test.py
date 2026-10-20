#!/usr/bin/env python3
"""Run real loopback workflows with private, synthetic media and owned servers."""
from pathlib import Path
import os, shutil, socket, subprocess, sys, tempfile, time
from test_servers import wait_for_servers
root=Path(__file__).resolve().parents[1]
logdir=root/'.test-output'
logdir.mkdir(exist_ok=True)
strict='--require-tools' in sys.argv[1:]
swift_args=[arg for arg in sys.argv[1:] if arg!='--require-tools']
if strict:
    if swift_args:sys.exit('Strict coverage runs the entire suite; Swift filters/options are not accepted.')
    missing=[tool for tool in ('ffmpeg','yt-dlp') if not shutil.which(tool)]
    if missing:sys.exit('Missing required tools: '+', '.join(missing))
ffmpeg=shutil.which('ffmpeg')
if not ffmpeg:
    sys.exit('Full integration tests require an existing FFmpeg installation. No software is installed by this script.')
for port in (18764,18765):
    with socket.socket() as probe:
        try:probe.bind(('127.0.0.1',port))
        except OSError:sys.exit(f'Loopback port {port} is in use. Stop the earlier test server before running this suite.')
servers=[]
with tempfile.TemporaryDirectory(prefix='streamdrop-fixture-') as temp:
    fixture=Path(temp)
    media=fixture/'sample.mp4'
    subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-f','lavfi','-i','color=c=0x8671e8:s=320x180:r=24','-f','lavfi','-i','sine=frequency=440:sample_rate=44100','-t','2','-c:v','libx264','-pix_fmt','yuv420p','-c:a','aac','-y',str(media)],check=True)
    vp9=fixture/'vp9.mp4'
    subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-i',str(media),'-c:v','libvpx-vp9','-b:v','200k','-threads','2','-c:a','copy','-y',str(vp9)],check=True)
    subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-i',str(media),'-c','copy','-hls_time','1','-hls_playlist_type','vod','-hls_segment_filename',str(fixture/'segment%03d.ts'),'-f','hls','-y',str(fixture/'playlist.m3u8')],check=True)
    try:
        env=dict(os.environ,STREAMDROP_FIXTURE_MEDIA=str(media),STREAMDROP_FIXTURE_VP9=str(vp9))
        with open(logdir/'servers.log','w') as server_log:
            servers.append(subprocess.Popen([sys.executable,'-u',str(root/'scripts/fixture-server.py')],env=env,stdout=server_log,stderr=subprocess.STDOUT))
            servers.append(subprocess.Popen([sys.executable,'-u','-m','http.server','18765','--bind','127.0.0.1','--directory',str(fixture)],stdout=server_log,stderr=subprocess.STDOUT))
            print(f'Fixture interpreter: {sys.executable}; PIDs: {[server.pid for server in servers]}',flush=True)
            wait_for_servers(servers,(18764,18765))
            started=time.monotonic()
            report=logdir/'tests.xml'
            report.unlink(missing_ok=True)
            env['STREAMDROP_XCTEST_REPORT']=str(report)
            result=subprocess.run(['swift','test',*swift_args],cwd=root,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
            (logdir/'tests.log').write_text(result.stdout)
            print(result.stdout,end='')
            print(f'Completed suite including Swift build: {time.monotonic()-started:.2f}s')
            code=result.returncode
            if code==0:
                gate=subprocess.run([sys.executable,str(root/'scripts/check-test-results.py'),str(report),*(['--strict'] if strict else [])])
                code=gate.returncode
    finally:
        for server in servers:
            if server.poll() is None:server.terminate()
        for server in servers:
            try:server.wait(timeout=5)
            except subprocess.TimeoutExpired:server.kill();server.wait()
sys.exit(code)
