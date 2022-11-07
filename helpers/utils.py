#!/usr/bin/env python3

import os
import sys
from typing import List, Dict
import re
import pwd
import subprocess
import logging
import io
from tempfile import NamedTemporaryFile

USER_HOME_DIR_ENT_IDX = 5
EXIT_CODE_BAD_KUBECONFIG = -100
EXIT_CODE_BAD_CONF_ARG = -200

def generate_spark_default_conf() -> Dict:
    generated_defaults = dict()
    USER_HOME_DIR = pwd.getpwuid(os.getuid())[USER_HOME_DIR_ENT_IDX]
    SCALA_HIST_FILE_DIR = os.environ.get('SNAP_USER_COMMON', USER_HOME_DIR)
    generated_defaults['spark.driver.extraJavaOptions'] = f'-Dscala.shell.histfile={SCALA_HIST_FILE_DIR}/.scala_history'
    return generated_defaults

def read_property_file(name: str) -> Dict :
    defaults = dict()
    with open(name) as f:
        for line in f:
            kv = list(filter(None, re.split('=| ', line.strip())))
            k = kv[0]
            v = '='.join(kv[1:])
            defaults[k] = os.path.expandvars(v)
    return defaults

def write_property_file(fp: io.TextIOWrapper, props: Dict, log: bool = None) -> None:
    for k in props.keys():
        v = props[k]
        line = f"{k}={v.strip()}"
        fp.write(line+'\n')
        if (log):
            logging.info(line)

def merge_configurations(dictionaries_to_merge: List[Dict]) -> Dict:
    result = dict()
    for override in dictionaries_to_merge:
        result.update(override)
    return result

def get_static_defaults_conf_file() -> str:
    SPARK_STATIC_DEFAULTS_FILE = f"{os.environ.get('SNAP')}/conf/spark-defaults.conf"
    return SPARK_STATIC_DEFAULTS_FILE

def get_dynamic_defaults_conf_file() -> str:
    SPARK_DYNAMIC_DEFAULTS_FILE = f"{os.environ.get('SNAP_USER_DATA')}/spark-defaults.conf"
    return SPARK_DYNAMIC_DEFAULTS_FILE

def get_env_defaults_conf_file() -> str:
    SPARK_ENV_DEFAULTS_FILE = os.environ.get('SNAP_SPARK_ENV_CONF')
    return SPARK_ENV_DEFAULTS_FILE

def get_snap_temp_dir() -> str:
    return '/tmp/snap.spark-client'

def parse_conf_overrides(conf_args: List) -> Dict:
    conf_overrides = dict()
    if conf_args:
        for c in conf_args:
            try:
                kv = c.split('=')
                k = kv[0]
                v = '='.join(kv[1:])
                conf_overrides[k] = os.environ.get(v, v)
            except IndexError as e:
                logging.error('Configuration related arguments parsing error. Please check input arguments and try again.')
                sys.exit(EXIT_CODE_BAD_CONF_ARG)
    return conf_overrides

def reconstruct_submit_args(args: List, conf: Dict) -> List:
    submit_args = args
    conf_arg = ''
    for k in conf.keys():
        conf_arg += f' --conf {k}={conf[k].strip()}'
    submit_args = [conf_arg] + submit_args
    return submit_args

def autodetect_kubernetes_master(conf: Dict) -> str:
    USER_HOME_DIR = pwd.getpwuid(os.getuid())[USER_HOME_DIR_ENT_IDX]
    DEFAULT_KUBECONFIG = f'{USER_HOME_DIR}/.kube/config'
    kubeconfig = os.environ.get('KUBECONFIG') or DEFAULT_KUBECONFIG
    kubectl_cmd = '{}/kubectl'.format(os.environ['SNAP'])
    context = conf.get('spark.kubernetes.context')
    if context:
        master_kubectl_cmd = f"{kubectl_cmd} --kubeconfig {kubeconfig} --context {context} config view --minify -o jsonpath=\"{{.clusters[0]['cluster.server']}}\""
    else:
        master_kubectl_cmd = f"{kubectl_cmd} --kubeconfig {kubeconfig} config view --minify -o jsonpath=\"{{.clusters[0]['cluster.server']}}\""
    try:
       default_master = subprocess.check_output(master_kubectl_cmd, shell=True)
       k8s_master_uri = 'k8s://' + default_master.decode("utf-8")
    except subprocess.CalledProcessError as e:
       logging.error(f'Cannot determine default kubernetes control plane url. Probably bad or missing kubeconfig file {kubeconfig}')
       logging.warning(f'Please set the KUBECONFIG environment variable to point to the kubeconfig. Or fix the default kubeconfig {kubeconfig}')
       logging.error(e.output)
       sys.exit(EXIT_CODE_BAD_KUBECONFIG)
    return k8s_master_uri

def UmaskNamedTemporaryFile(*args, **kargs):
    fdesc = NamedTemporaryFile(*args, **kargs)
    umask = os.umask(0o666)
    os.umask(umask)
    os.chmod(fdesc.name, 0o666 & ~umask)
    return fdesc