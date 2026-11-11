#!/usr/bin/env python3
"""Green Fish — monta o app a partir das fontes desta pasta.

Uso (na pasta green-fish):
  python3 fonte/montar.py              -> gera index.html com a versão atual do sw.js
  python3 fonte/montar.py --nova       -> sobe a versão (ex.: ras-v185 -> ras-v186) e gera index.html
  python3 fonte/montar.py --desktop    -> também gera Sistema_RAS_Multitanques.html (cópia para abrir no computador)

Fontes:
  fonte/app.html             o app inteiro (abas, Calculadora, desenho técnico, mapas, Painel…)
  fonte/aquanictemeral.html  a aba AquaNictemeral (vai embutida no app, no lugar de __AQUANICTEMERAL__)
"""
import html, os, re, sys

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
ler = lambda p: open(p, encoding="utf8").read()

def versao(nova):
    sw = os.path.join(RAIZ, "sw.js"); t = ler(sw)
    m = re.search(r'const VERSAO = "ras-v(\d+)";', t)
    if not m: sys.exit("Não achei a versão no sw.js")
    v = int(m.group(1))
    if nova:
        v += 1; t = t.replace(m.group(0), f'const VERSAO = "ras-v{v}";'); open(sw, "w", encoding="utf8").write(t)
    return f"ras-v{v}"

def main():
    nova, desk = "--nova" in sys.argv, "--desktop" in sys.argv
    app, aqua = ler(os.path.join(AQUI, "app.html")), ler(os.path.join(AQUI, "aquanictemeral.html"))
    if app.count("__AQUANICTEMERAL__") != 1: sys.exit("app.html precisa ter __AQUANICTEMERAL__ uma vez (no data-srcdoc do aqua-frame)")
    s = app.replace("__AQUANICTEMERAL__", html.escape(aqua, quote=True))
    v = versao(nova)
    a = '<meta name="claude:viewport-fit-sides" content="cover">\n'
    if s.count(a) != 1: sys.exit("Não achei a linha <meta name=\"claude:viewport-fit-sides\"> no app.html")
    if desk:
        cfg = ler(os.path.join(RAIZ, "config.js")); m = re.search(r"window\.RAS_CONFIG = \{.*?\};", cfg, re.S)
        if m:
            c = m.group(0).replace("adminNoCelular: false", 'adminNoCelular: false,\n  appUrl: "https://jpribeiro-aqua.github.io/green-fish/"')
            d = s.replace(a, a + "<script>\n/* Cópia do computador: usa a mesma conta do app (Supabase) que o app do celular */\n" + c + "\n</script>\n")
            open(os.path.join(RAIZ, "Sistema_RAS_Multitanques.html"), "w", encoding="utf8").write(d.replace('"__APP_VERSAO__"', '"' + v + '"'))
    s = s.replace(a, '''<meta name="theme-color" content="#0f7a6c">
<link rel="manifest" href="manifest.webmanifest">
<link rel="icon" type="image/png" href="favicon-64.png">
<link rel="apple-touch-icon" href="apple-touch-icon.png">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="Green Fish">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
<script src="config.js"></script>
''')
    s = s.replace('"__APP_VERSAO__"', '"' + v + '"')
    open(os.path.join(RAIZ, "index.html"), "w", encoding="utf8").write(s)
    print(f"✓ index.html montado ({len(s)//1024} KB) · versão {v}" + (" · nova versão" if nova else "") + (" · + Sistema_RAS_Multitanques.html" if desk else ""))
    print("Próximo passo: GitHub Desktop › Commit › Push (o site atualiza em ~2 min).")

if __name__ == "__main__":
    main()
