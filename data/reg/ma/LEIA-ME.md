# Áreas certificadas do INCRA (SIGEF / SNCI) para o Green Fish

Três caminhos — qualquer um gera os arquivos que o app importa em
**Camada de mercado → 🌾 Prospecção rural → 🏛️ Áreas regularizadas → 📥 Importar arquivo**.

## 1. Arquivo do INCRA (mais rápido)
1. No Safari, abra https://certificacao.incra.gov.br/csv_shp/export_shp.py
2. Escolha **Imóvel certificado SIGEF – particular** (depois repita para SIGEF público, SNCI privado e SNCI público) e o estado **MA**.
3. Salve os .zip **nesta pasta** (10_sigef_incra). O Claude lê, recorta a sua área e carrega no app.
   (Assentamentos: https://acervofundiario.incra.gov.br/acervo/acv.php → Download → Shapefile → Assentamentos → MA.)

## 2. QGIS
1. Baixe o QGIS em https://qgis.org/download/ (macOS, versão LTR) e instale.
2. QGIS → Complementos → Terminal Python → Mostrar editor → abrir `baixar_sigef_qgis.py` → ▶.
3. Os .geojson aparecem nesta pasta (só a sua região; mude `RECORTE` para `None` para o estado todo).

## 3. Liberar o INCRA para o Claude
Em claude.ai → Configurações da organização → Capabilities → domínios permitidos, adicione
`acervofundiario.incra.gov.br` e `certificacao.incra.gov.br`. Aí o Claude baixa direto com o GDAL (motor do QGIS).

LGPD: nome, CPF e CNPJ de detentores não são guardados no app.
