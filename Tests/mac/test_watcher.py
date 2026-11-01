"""Run the real watcher control flow with every OS network command replaced by a fake.
No sudo, host networking, launchd, or real DNS is used.
"""
import json
import os
import fcntl
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
MOCK = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p=Path(os.environ['MOCK_ROOT']); state=json.loads((p/'state.json').read_text())
tool=sys.argv[1]; a=sys.argv[2:]; code=0
if tool=='networksetup' and a[0]=='-getdnsservers' and state.get('pause_on_get'):
 import time
 (p/'paused').touch()
 until=time.monotonic()+5
 while not (p/'release').exists() and time.monotonic()<until: time.sleep(0.01)
with (p/'calls').open('a') as f: f.write(json.dumps([tool]+a)+'\n')
if tool=='ifconfig':
 if a: code=0 if state['healthy'] else 1
 elif state['hotspot']: print('en9: flags=UP\n\tinet 172.20.10.2 netmask 0xfffffff0')
 else: print('en0: flags=UP\n\tinet 192.168.1.2')
elif tool=='nc': code=0 if state['proxy'] else 1
elif tool=='dig':
 if state['healthy']: print(';; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1')
 else: code=1
elif tool=='launchctl':
 if a[0]=='print':
  if 'tailscaled' in a[1]: code=1
  elif state['registered']: print('state = running' if state['healthy'] else 'state = waiting')
  else: code=1
 elif a[0]=='bootstrap':
  code=0 if state['bootstrap'] else 1
  if code==0: state['registered']=True
 elif a[0]=='bootout': state['registered']=False
elif tool=='networksetup':
 if a[0]=='-listnetworkserviceorder': print('(1) USB Hotspot\n(Hardware Port: iPhone USB, Device: en9)')
 elif a[0]=='-getdnsservers':
  if state.get('get_fail'): code=1
  else: print("There aren't any DNS Servers set on USB Hotspot." if state['dns']==['Empty'] else '\n'.join(state['dns']))
 elif a[0]=='-setdnsservers':
  if state.get('restore_fail') and a[2:] != ['172.19.0.2']: code=1
  elif state.get('set_fail'): code=1
  elif state.get('ignore_restore') and a[2:] != ['172.19.0.2']: pass
  else: state['dns']=a[2:]
(p/'state.json').write_text(json.dumps(state))
if tool=='networksetup' and a[0]=='-setdnsservers' and state.get('crash_after_dns'):
 import signal
 os.kill(os.getppid(), signal.SIGKILL)
sys.exit(code)
'''

class WatcherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='hotspot-watcher-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        mock = self.root / 'mock'; mock.write_text(MOCK); mock.chmod(0o755)
        source = (ROOT/'mac/hotspot-tun.sh').read_text()
        source = source.replace('/usr/local/var/hotspot-tun', str(self.root/'runtime'))
        source = source.replace('mkdir -p /usr/local/var', 'mkdir -p ' + str(self.root))
        for path, tool in [('/sbin/ifconfig','ifconfig'),('/usr/bin/nc','nc'),('/usr/bin/dig','dig'),('/bin/launchctl','launchctl'),('/usr/sbin/networksetup','networksetup'),('/bin/sleep','sleep')]:
            source=source.replace(path, str(mock)+' '+tool)
        self.script=self.root/'watch.sh'; self.script.write_text(source)
        self.save(dict(hotspot=True, proxy=True, registered=False, healthy=True, bootstrap=True, dns=['9.9.9.9','149.112.112.112']))
    def load(self): return json.loads((self.root/'state.json').read_text())
    def save(self, state): (self.root/'state.json').write_text(json.dumps(state))
    def change(self, **values):
        state=self.load();state.update(values);self.save(state)
    def run_watcher(self, *args):
        return subprocess.run(['bash',str(self.script),*args], env=dict(os.environ, MOCK_ROOT=str(self.root)), capture_output=True, text=True)
    def test_bootstrap_failure_never_changes_dns(self):
        self.change(bootstrap=False)
        self.assertNotEqual(self.run_watcher().returncode, 0)
        self.assertEqual(self.load()['dns'], ['9.9.9.9','149.112.112.112'])
    def test_registered_but_unhealthy_tun_never_changes_dns(self):
        self.change(registered=True,healthy=False)
        self.assertEqual(self.run_watcher().returncode,0)
        self.assertEqual(self.load()['dns'], ['9.9.9.9','149.112.112.112'])
        self.assertFalse(self.load()['registered'])
    def test_original_dns_and_service_restored(self):
        self.assertEqual(self.run_watcher().returncode,0)
        self.assertEqual(self.load()['dns'],['172.19.0.2'])
        # Repeated activation must not replace the original backup with TUN DNS.
        self.assertEqual(self.run_watcher().returncode,0)
        self.change(hotspot=False)
        self.assertEqual(self.run_watcher().returncode,0)
        self.assertEqual(self.load()['dns'],['9.9.9.9','149.112.112.112'])
        calls=[json.loads(line) for line in (self.root/'calls').read_text().splitlines()]
        changes=[c for c in calls if c[:2]==['networksetup','-setdnsservers']]
        self.assertTrue(all(c[2]=='USB Hotspot' for c in changes))
    def test_dhcp_dns_restored(self):
        self.change(dns=['Empty']);self.run_watcher();self.change(hotspot=False);self.run_watcher()
        self.assertEqual(self.load()['dns'],['Empty'])
    def test_user_dns_change_not_overwritten_on_stop(self):
        self.run_watcher();self.change(dns=['8.8.8.8']);self.run_watcher('--stop')
        self.assertEqual(self.load()['dns'],['8.8.8.8'])
    def test_restoration_failure_preserves_backup_and_tun(self):
        self.run_watcher();self.change(restore_fail=True)
        self.assertNotEqual(self.run_watcher('--stop').returncode,0)
        self.assertTrue((self.root/'runtime/dns-state/servers').exists())
        self.assertTrue(self.load()['registered'])
        self.change(restore_fail=False);self.assertEqual(self.run_watcher('--stop').returncode,0)
        self.assertEqual(self.load()['dns'],['9.9.9.9','149.112.112.112'])
    def test_active_tun_failure_restores_dns(self):
        self.run_watcher();self.change(healthy=False);self.run_watcher()
        self.assertEqual(self.load()['dns'],['9.9.9.9','149.112.112.112'])
    def test_unowned_tun_dns_is_not_guessed(self):
        self.change(dns=['172.19.0.2']);self.run_watcher()
        self.assertFalse((self.root/'runtime/dns-state').exists())
        self.assertEqual(self.load()['dns'],['172.19.0.2'])
    def test_dns_read_failure_does_not_write_dns(self):
        self.change(get_fail=True);self.run_watcher()
        self.assertEqual(self.load()['dns'],['9.9.9.9','149.112.112.112'])
    def test_live_lock_prevents_changes(self):
        with (self.root/'runtime.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertNotEqual(self.run_watcher().returncode,0)
            self.assertEqual(self.load()['dns'],['9.9.9.9','149.112.112.112'])
    def test_crash_after_dns_change_releases_lock_and_restores_backup(self):
        self.change(crash_after_dns=True)
        self.assertNotEqual(self.run_watcher().returncode,0)
        self.assertEqual(self.load()['dns'],['172.19.0.2'])
        self.assertTrue((self.root/'runtime/dns-state/servers').exists())
        self.change(crash_after_dns=False)
        self.assertEqual(self.run_watcher('--stop').returncode,0)
        self.assertEqual(self.load()['dns'],['9.9.9.9','149.112.112.112'])
    def test_recovery_of_uncommitted_backup(self):
        # Crash between publishing the backup and changing DNS: do not replace it with TUN DNS.
        backup=self.root/'runtime/dns-state';backup.mkdir(parents=True)
        (backup/'service').write_text('USB Hotspot\n')
        (backup/'servers').write_text('9.9.9.9\n149.112.112.112\n')
        self.assertEqual(self.run_watcher().returncode,0)
        self.assertEqual(self.run_watcher('--stop').returncode,0)
        self.assertEqual(self.load()['dns'],['9.9.9.9','149.112.112.112'])
    def test_restore_success_exit_without_actual_change_retains_backup(self):
        self.run_watcher();self.change(ignore_restore=True)
        self.assertNotEqual(self.run_watcher('--stop').returncode,0)
        self.assertTrue((self.root/'runtime/dns-state/servers').exists())
        self.assertTrue(self.load()['registered'])
    def test_concurrent_stop_cannot_overlap_activation(self):
        self.change(pause_on_get=True)
        process=subprocess.Popen(['bash',str(self.script)],env=dict(os.environ,MOCK_ROOT=str(self.root)),stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        try:
            until=time.monotonic()+3
            while not (self.root/'paused').exists() and time.monotonic()<until: time.sleep(0.01)
            self.assertTrue((self.root/'paused').exists())
            self.assertNotEqual(self.run_watcher('--stop').returncode,0)
            (self.root/'release').touch()
            process.communicate(timeout=5)
            self.assertEqual(process.returncode,0)
            self.change(pause_on_get=False)
            self.assertEqual(self.run_watcher('--stop').returncode,0)
            self.assertEqual(self.load()['dns'],['9.9.9.9','149.112.112.112'])
        finally:
            if process.poll() is None: process.kill();process.communicate()
    def test_crash_after_restore_can_complete_cleanup(self):
        self.run_watcher();self.change(crash_after_dns=True)
        self.assertNotEqual(self.run_watcher('--stop').returncode,0)
        self.assertEqual(self.load()['dns'],['9.9.9.9','149.112.112.112'])
        self.change(crash_after_dns=False)
        self.assertEqual(self.run_watcher('--stop').returncode,0)
        self.assertFalse((self.root/'runtime/dns-state').exists())
    def test_nested_lifecycle_command_inherits_the_same_lock(self):
        # Simulate installer/uninstaller keeping the lock while calling watcher --stop.
        source=self.script.read_text()
        begin=source.index('# Kernel advisory lock;')
        end=source.index('mkdir -p "$STATE"',begin)
        parent=self.root/'parent.sh'
        parent.write_text('#!/bin/bash\n'+source[begin:end]+'\nbash '+str(self.script)+' --stop\n')
        self.run_watcher()
        result=subprocess.run(['bash',str(parent)],env=dict(os.environ,MOCK_ROOT=str(self.root)),capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(self.load()['dns'],['9.9.9.9','149.112.112.112'])
    def test_set_failure_can_retry_without_losing_original(self):
        self.change(set_fail=True);self.run_watcher()
        self.assertEqual(self.load()['dns'],['9.9.9.9','149.112.112.112'])
        self.change(set_fail=False);self.run_watcher();self.run_watcher('--stop')
        self.assertEqual(self.load()['dns'],['9.9.9.9','149.112.112.112'])

if __name__=='__main__': unittest.main()
