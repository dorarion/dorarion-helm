#!/usr/bin/env python3
"""Local k3d chart installation/upgrade acceptance with isolated DB and namespace.

Requires .env, .dev-tools/listener.env, a provisioned restricted receiver role,
local images, Argo Application CRD, and the development Docker/k3d network.
"""
import os,subprocess,json,secrets,hashlib,time,base64,urllib.request
from pathlib import Path
from urllib.parse import urlsplit,unquote,quote
chart=Path(os.environ.get('DORARION_HELM_CHART',Path(__file__).resolve().parents[2])).resolve()
root=Path(os.environ.get('DORARION_CORE_DIR',chart.parent/'dorarion-core')).resolve();os.chdir(root)
core_image=os.environ.get('DORARION_HELM_CORE_IMAGE','docker.io/library/dorarion-core:helm-test')
listener_image=os.environ.get('DORARION_HELM_LISTENER_IMAGE','docker.io/library/dorarion-listener:helm-test')
def image_values(image):
 repository,tag=image.rsplit(':',1)
 return {'repository':repository,'tag':tag,'digest':''}
namespace='dorarion-helm-'+secrets.token_hex(4);db=namespace.replace('-','_');work=Path('/tmp')/namespace;work.mkdir(mode=0o700)
env=os.environ.copy();env.setdefault('KUBECONFIG',str(root/'.dev-tools/kubeconfig-dorarion'))
kubectl=os.environ.get('DORARION_KUBECTL',str(root/'.dev-tools/bin/kubectl'))
def run(args,input=None,check=True):
 r=subprocess.run(args,env=env,input=input,text=True,capture_output=True)
 if check and r.returncode:raise RuntimeError('command failed '+args[0]+' '+args[1]+': '+r.stderr[:1000])
 return r.stdout.strip()
def kube(*args,obj=None):return run([kubectl,*args],input=json.dumps(obj) if obj is not None else None)
cfg={l.split('=',1)[0]:l.split('=',1)[1].strip().strip('\"\'') for l in Path('.env').read_text().splitlines() if l and not l.startswith('#') and '=' in l};u=urlsplit(cfg['DATABASE_URL'])
env.update(PGHOST=u.hostname,PGPORT=str(u.port or 5432),PGUSER=unquote(u.username),PGPASSWORD=unquote(u.password),PGDATABASE='postgres')
def sql(query,database='postgres'):
 return run(['psql','-XAtq','-v','ON_ERROR_STOP=1','-d',database],input=query)
listener_cfg={l.split('=',1)[0]:l.split('=',1)[1].strip().strip('\"\'') for l in Path('.dev-tools/listener.env').read_text().splitlines() if l and not l.startswith('#') and '=' in l};lu=urlsplit(listener_cfg['DATABASE_URL'])
pgip=run(['docker','inspect','--format','{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}','dorarion_postgres'])
coreurl=f'postgres://{quote(unquote(u.username))}:{quote(unquote(u.password))}@{pgip}:5432/{db}'
listenerurl=f'postgres://{quote(unquote(lu.username))}:{quote(unquote(lu.password))}@{pgip}:5432/{db}'
password=secrets.token_urlsafe(32);watchtoken=secrets.token_urlsafe(32)
def secret(name,values):
 kube('apply','-f','-',obj={'apiVersion':'v1','kind':'Secret','metadata':{'name':name,'namespace':namespace},'type':'Opaque','stringData':values})
try:
 sql('CREATE DATABASE "'+db+'"');kube('create','namespace',namespace)
 secret('dorarion-secrets',{'DATABASE_URL':coreurl,'JWT_SECRET':secrets.token_urlsafe(48),'SECRET_ENCRYPTION_KEY':base64.b64encode(secrets.token_bytes(32)).decode(),'DORARION_BOOTSTRAP_PASSWORD':password})
 secret('dorarion-listener-secrets',{'DATABASE_URL':listenerurl});secret('dorarion-watcher-secrets',{'LISTENER_WATCHER_TOKEN':watchtoken})
 for image in [core_image,listener_image,'nginx:1.27-alpine']:
  save=subprocess.Popen(['docker','save',image],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  load=subprocess.run(['docker','exec','-i',os.environ.get('DORARION_K3D_NODE','k3d-dorarion-server-0'),'ctr','--namespace','k8s.io','images','import','--platform','linux/amd64','-'],env=env,stdin=save.stdout,stdout=subprocess.PIPE,stderr=subprocess.PIPE);save.stdout.close();assert save.wait()==0 and load.returncode==0,'local image import failed'
 print('Local core, receiver and TLS proxy images imported into Kubernetes',flush=True)
 host=f'listener-tls.{namespace}.svc'
 run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(work/'ca-key.pem'),'-out',str(work/'ca.pem'),'-days','1','-subj','/CN=Dorarion local acceptance CA','-addext','basicConstraints=critical,CA:TRUE','-addext','keyUsage=critical,keyCertSign,cRLSign'])
 run(['openssl','req','-new','-newkey','rsa:2048','-nodes','-keyout',str(work/'key.pem'),'-out',str(work/'server.csr'),'-subj','/CN='+host])
 (work/'server.ext').write_text('basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:'+host+'\n')
 run(['openssl','x509','-req','-in',str(work/'server.csr'),'-CA',str(work/'ca.pem'),'-CAkey',str(work/'ca-key.pem'),'-CAcreateserial','-out',str(work/'cert.pem'),'-days','1','-extfile',str(work/'server.ext')])
 for private in ['key.pem','ca-key.pem']:os.chmod(work/private,0o600)
 secret('listener-ca',{'tls.crt':(work/'cert.pem').read_text(),'tls.key':(work/'key.pem').read_text(),'ca.crt':(work/'ca.pem').read_text()})
 nginx=f'events {{}}\nhttp {{ server {{ listen 8443 ssl; ssl_certificate /tls/tls.crt; ssl_certificate_key /tls/tls.key; location / {{ proxy_pass http://acceptance-listener:8080; }} }} }}'
 kube('apply','-f','-',obj={'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':'listener-tls','namespace':namespace},'data':{'nginx.conf':nginx}})
 kube('apply','-f','-',obj={'apiVersion':'apps/v1','kind':'Deployment','metadata':{'name':'listener-tls','namespace':namespace},'spec':{'replicas':1,'selector':{'matchLabels':{'app':'listener-tls'}},'template':{'metadata':{'labels':{'app':'listener-tls'}},'spec':{'containers':[{'name':'nginx','image':'nginx:1.27-alpine','volumeMounts':[{'name':'config','mountPath':'/etc/nginx/nginx.conf','subPath':'nginx.conf'},{'name':'tls','mountPath':'/tls','readOnly':True}]}],'volumes':[{'name':'config','configMap':{'name':'listener-tls'}},{'name':'tls','secret':{'secretName':'listener-ca'}}]}}}})
 kube('apply','-f','-',obj={'apiVersion':'v1','kind':'Service','metadata':{'name':'listener-tls','namespace':namespace},'spec':{'selector':{'app':'listener-tls'},'ports':[{'port':8443,'targetPort':8443}]}})
 values={'image':image_values(core_image),'publicUrl':'http://127.0.0.1:3000','allowInsecurePublicUrl':True,'database':{'trustedHosts':[pgip]},'bootstrapAdmin':{'enabled':True,'email':'admin@example.invalid'},'listener':{'enabled':True,'image':image_values(listener_image),'trustedDatabaseHosts':[pgip],'watcher':{'enabled':True,'receiverUrl':'https://'+host+':8443','namespaces':[namespace]},'extraEnv':[{'name':'LISTENER_EXTRA_CA_FILE','value':'/listener-ca/tls.crt'}],'extraVolumes':[{'name':'ca','secret':{'secretName':'listener-ca','items':[{'key':'ca.crt','path':'tls.crt'}]}}],'extraVolumeMounts':[{'name':'ca','mountPath':'/listener-ca','readOnly':True}]}}
 (work/'values.json').write_text(json.dumps(values))
 run(['helm','install','acceptance',str(chart),'-n',namespace,'-f',str(work/'values.json'),'--wait','--timeout','5m'])
 print('Helm install: migration hook, bootstrap hook, core and two receivers ready',flush=True)
 integration=sql("INSERT INTO integrations(name,provider,base_url) VALUES('Helm watcher','argocd','https://argocd.example.invalid') RETURNING id",db)
 sql("INSERT INTO listener_watchers(name,integration_id,token_sha256,auto_register) VALUES('Helm watcher',"+integration+",decode('"+hashlib.sha256(watchtoken.encode()).hexdigest()+"','hex'),true)",db)
 # Credential cache refresh is bounded; watcher heartbeat proves TLS and restricted DB path.
 deadline=time.monotonic()+180
 while time.monotonic()<deadline:
  if sql("SELECT count(*) FROM listener_watchers WHERE last_seen_at IS NOT NULL",db)=='1':break
  time.sleep(2)
 else:raise AssertionError('watcher TLS heartbeat did not reach core')
 leases=json.loads(kube('get','leases','-n',namespace,'-o','json'));assert any(x['spec'].get('holderIdentity') for x in leases['items'])
 deployments=json.loads(kube('get','deployments','-n',namespace,'-o','json'));assert any(x['metadata']['name']=='acceptance-listener-watcher' and x['status'].get('readyReplicas')==2 for x in deployments['items'])
 print('Helm watcher: two replicas, Kubernetes Lease leadership and HTTPS heartbeat through receiver/core passed',flush=True)
 application={'apiVersion':'argoproj.io/v1alpha1','kind':'Application','metadata':{'name':'helm-watcher-acceptance','namespace':namespace,'labels':{'dorarion.io/track':'true'}},'spec':{'project':'default','source':{'repoURL':'https://gitlab.example.invalid/acceptance/app','path':'.','targetRevision':'main'},'destination':{'server':'https://kubernetes.default.svc','namespace':namespace}}}
 kube('apply','-f','-',obj=application)
 kube('patch','application','helm-watcher-acceptance','-n',namespace,'--type=merge','--patch',json.dumps({'status':{'sync':{'status':'Synced','revision':'helm-test-revision'},'health':{'status':'Healthy'}}}))
 deadline=time.monotonic()+60
 while time.monotonic()<deadline:
  if sql("SELECT count(*) FROM listener_pending_applications WHERE application_name='helm-watcher-acceptance'",db)=='1':break
  time.sleep(1)
 else:raise AssertionError('Application observation did not reach pending approval')
 lease=json.loads(kube('get','lease','acceptance-listener-watcher','-n',namespace,'-o','json'))
 leader=lease['spec']['holderIdentity']
 started=time.monotonic();kube('delete','pod',leader,'-n',namespace,'--grace-period=0','--force','--wait=false')
 while time.monotonic()-started<45:
  holder=json.loads(kube('get','lease','acceptance-listener-watcher','-n',namespace,'-o','json'))['spec'].get('holderIdentity')
  if holder and holder!=leader:break
  time.sleep(1)
 else:raise AssertionError('Helm watcher leader takeover exceeded 45 seconds')
 assert sql("SELECT count(*) FROM listener_pending_applications WHERE application_name='helm-watcher-acceptance'",db)=='1'
 print('Helm Application observation, pending approval and leader takeover %.2fs: passed'%(time.monotonic()-started),flush=True)

 run(['helm','upgrade','acceptance',str(chart),'-n',namespace,'-f',str(work/'values.json'),'--wait','--timeout','5m'])
 print('Helm upgrade: migration hook and workload readiness passed',flush=True)
finally:
 run(['helm','uninstall','acceptance','-n',namespace],check=False)
 run([kubectl,'delete','namespace',namespace,'--wait=true','--timeout=120s'],check=False)
 sql('DROP DATABASE IF EXISTS "'+db+'" WITH (FORCE)')
 print('Isolated Helm namespace and database removed',flush=True)
