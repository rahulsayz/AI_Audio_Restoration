# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_dynamic_libs
from PyInstaller.utils.hooks import collect_all
from PyInstaller.utils.hooks import copy_metadata

datas = []
binaries = []
hiddenimports = ['torch', 'torchaudio', 'soundfile', 'structlog', 'grpcio', 'numpy', 'scipy', 'deepfilternet', 'pyloudnorm', 'ssr_eval', 'sangeet', 'sangeet.v1', 'sangeet.v1.restoration_pb2', 'sangeet.v1.restoration_pb2_grpc', 'df', 'df.deepfilternet3', 'df.enhance', 'df.model', 'df.io']
datas += copy_metadata('torch')
datas += copy_metadata('torchaudio')
binaries += collect_dynamic_libs('soundfile')
tmp_ret = collect_all('torch')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('sangeet')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('df')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('deepfilternet')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]


a = Analysis(
    ['sangeet_inference/daemon.py'],
    pathex=['sangeet_inference/proto'],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['torch.cuda', 'caffe2', 'triton', 'tensorboard', 'torchvision', 'torchaudio.lib.libtorchaudio_cuda'],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='sangeet-inference',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='sangeet-inference',
)
