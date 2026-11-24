#!/usr/bin/env python3
"""Green Fish — copia o app montado para o repositório do domínio novo (greenfish.app.br).

Uso (na pasta green-fish, depois de montar.py):
  python3 fonte/espelhar.py
Copia index.html, sw.js, manifest, ícones e config.js para ../greenfish-app e grava o arquivo CNAME.
Depois: GitHub Desktop › greenfish-app › Commit › Push.
"""
import os, re, shutil, sys
AQUI = os.path.dirname(os.path.abspath(__file__)); RAIZ = os.path.dirname(AQUI)
DEST = os.path.join(os.path.dirname(RAIZ), "greenfish-app")
DOMINIO = "greenfish.app.br"
ARQS = ["index.html", "sw.js", "manifest.webmanifest", "icon-192.png", "icon-512.png", "maskable-512.png", "apple-touch-icon.png", "favicon-64.png"]
if not os.path.isdir(DEST): sys.exit(f"Não achei a pasta {DEST}")
for a in ARQS:
    shutil.copyfile(os.path.join(RAIZ, a), os.path.join(DEST, a))
cfg = open(os.path.join(RAIZ, "config.js"), encoding="utf8").read()
if "appUrl" in cfg: cfg = re.sub(r'appUrl:\s*"[^"]*"', f'appUrl: "https://{DOMINIO}/"', cfg)
else: cfg = cfg.replace("adminNoCelular: false", f'adminNoCelular: false,\n  appUrl: "https://{DOMINIO}/"', 1)
open(os.path.join(DEST, "config.js"), "w", encoding="utf8").write(cfg)
open(os.path.join(DEST, "CNAME"), "w").write(DOMINIO + "\n")
v = re.search(r'const VERSAO = "([^"]+)"', open(os.path.join(RAIZ, "sw.js"), encoding="utf8").read())
print(f"✓ greenfish-app atualizado ({v.group(1) if v else '?'}) · domínio {DOMINIO}")
print("Próximo passo: GitHub Desktop › greenfish-app › Commit › Push.")
