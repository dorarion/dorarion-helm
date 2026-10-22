#!/usr/bin/env python3
"""Verify shared startup policy and required configuration on all workloads."""
import sys
import yaml
resources=list(yaml.safe_load_all(sys.stdin))
workloads=[r for r in resources if r and r['kind'] in ('Deployment','Job')]
assert len(workloads)==3, 'server, migration and bootstrap workloads are required'
shared={'DORARION_DATABASE_TRUSTED_HOSTS':'db.internal','DORARION_DB_STATEMENT_TIMEOUT_MS':'45000','DORARION_SECRET_ENV_ALLOWLIST':'LEGACY_EXTERNAL','DORARION_TRUSTED_PROXIES':'10.0.0.0/24','DORARION_REPORT_RECIPIENT_DOMAINS':'example.com','DORARION_README_IMAGE_ORIGINS':'https://gitlab.example.com'}
for r in workloads:
    spec=r['spec']['template']['spec'];container=spec['containers'][0];env={v['name']:v for v in container['env']}
    assert all(env[k]['value']==v for k,v in shared.items()),r['metadata']['name']
    for name in ('DATABASE_URL','JWT_SECRET','SECRET_ENCRYPTION_KEY'):
        assert env[name]['valueFrom']['secretKeyRef']['name']=='dorarion-secrets',name
    assert env['JWT_ISSUER']['value']=='dorarion-core' and env['JWT_AUDIENCE']['value']=='dorarion-api'
    assert env['DORARION_METRICS_SCRAPE_TOKEN']['valueFrom']['secretKeyRef']['key']=='METRICS_TOKEN'
    assert container['envFrom']==[{'secretRef':{'name':'external-credentials'}}]
    assert spec['automountServiceAccountToken'] is False
    if r['kind']=='Deployment':
        assert env['DB_CONNECTION_POOL_SIZE']['value']=='15'
        assert env['DORARION_MIGRATE_ON_START']['value']=='false'
        assert env['DORARION_COOKIE_SECURE']['value']=='true'
        assert container['readinessProbe']['httpGet']['path']=='/health/ready'
        assert container['livenessProbe']['httpGet']['path']=='/health/live'
        assert spec['terminationGracePeriodSeconds']>=60
    else:
        assert env['DB_CONNECTION_POOL_SIZE']['value']=='1'
print('Shared startup policy and required credentials verified across all workloads.')
