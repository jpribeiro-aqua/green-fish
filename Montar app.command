#!/bin/bash
# Green Fish — monta o index.html a partir da pasta fonte/ (dê dois cliques neste arquivo no Finder)
cd "$(dirname "$0")" || exit 1
echo "Green Fish · montando o app…"
echo
echo "1) Nova versão (para publicar)   2) Mesma versão (só testar)   3) Nova versão + cópia do computador"
read -r -p "Escolha 1, 2 ou 3 [1]: " op
case "$op" in
  2) python3 fonte/montar.py ;;
  3) python3 fonte/montar.py --nova --desktop ;;
  *) python3 fonte/montar.py --nova ;;
esac
echo
read -r -p "Pronto. Agora publique no GitHub Desktop (Commit › Push). Aperte Enter para fechar." _
