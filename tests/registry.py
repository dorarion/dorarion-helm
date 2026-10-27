#!/usr/bin/env python3
"""Exercise parent registry propagation on rendered workloads and standalone use."""
from pathlib import Path
import subprocess
import os
import yaml

root = Path(__file__).resolve().parents[1]
chart = Path(os.environ.get('DORARION_HELM_CHART', root))
digest = 'sha256:' + 'a' * 64

def render(path, overrides):
    args = ['helm', 'template', 'registry-test', str(path)]
    for key, value in overrides.items():
        args.extend(['--set', f'{key}={value}'])
    docs = list(yaml.safe_load_all(subprocess.check_output(args, text=True)))
    workloads = [doc for doc in docs if doc and doc['kind'] in ('Deployment', 'Job')]
    identities = [(doc['kind'], doc['metadata']['name']) for doc in workloads]
    assert len(identities) == len(set(identities)), 'duplicate workload rendered'
    return [container['image'] for doc in workloads for container in doc['spec']['template']['spec']['containers']]

base = {'publicUrl':'https://dorarion.test', 'image.tag':'test',
        'bootstrapAdmin.enabled':'true', 'bootstrapAdmin.email':'admin@example.invalid',
        'listener.enabled':'true', 'listener.watcher.enabled':'true',
        'listener.watcher.receiverUrl':'https://receiver.test',
        'image.digest':digest, 'listener.image.digest':digest}
for extra, registry in [({'image.registry':'registry.corp:5000'}, 'registry.corp:5000'),
                        ({'global.imageRegistry':'global.corp','image.registry':'parent.corp','listener.image.registry':'child.corp'}, 'global.corp')]:
    images = render(chart, base | extra)
    assert len(images) == 5, images
    assert all(image.startswith(registry + '/') and image.endswith('@'+digest) for image in images), images
    assert sum('/dorarion-listener@' in image for image in images) == 2
images = render(chart, base | {'listener.enabled':'false', 'image.registry':'registry.corp'})
assert len(images) == 3 and all(image.startswith('registry.corp/') for image in images)
images = render(chart, base | {'listener.renderFromParent':'false'})
assert len(images) == 5, 'standalone-style child rendering must not duplicate parent workloads'
images = render(chart, base | {'image.registry':'registry.corp','image.repository':'kimc1992/dorarion-core'})
assert sum(image.startswith('registry.corp/kimc1992/dorarion-core@') for image in images) == 3, 'Docker Hub namespace must survive mirroring'
images = render(chart / 'charts/dorarion-listener', {'watcher.enabled':'true', 'watcher.receiverUrl':'https://receiver.test'})
assert len(images) == 2 and all(image.startswith('docker.io/') for image in images)
print('Helm registry: parent/global overrides, digest preservation, no duplicate workloads, disabled/standalone listener passed')

# A private parent registry must authenticate receiver and watcher as well.
for path, overrides in [(chart, base | {'imagePullSecrets[0].name':'private-registry'}),
                        (chart / 'charts/dorarion-listener', {'watcher.enabled':'true','watcher.receiverUrl':'https://receiver.test','imagePullSecrets[0].name':'private-registry'})]:
    args=['helm','template','pull-test',str(path)]
    for key,value in overrides.items():args.extend(['--set',f'{key}={value}'])
    docs=list(yaml.safe_load_all(subprocess.check_output(args,text=True)))
    workloads=[doc for doc in docs if doc and doc['kind'] in ('Deployment','Job')]
    assert all(doc['spec']['template']['spec'].get('imagePullSecrets')==[{'name':'private-registry'}] for doc in workloads)
print('Parent and standalone private registry pull credentials reach every workload')
