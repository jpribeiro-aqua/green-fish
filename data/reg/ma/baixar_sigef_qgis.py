# Green Fish — baixa as áreas certificadas do INCRA (SIGEF e SNCI) e os assentamentos pelo QGIS.
# Como usar: QGIS → menu Complementos → Terminal Python → ícone "Mostrar editor" → Abrir este arquivo → ▶ Executar.
# Os arquivos GeoJSON saem nesta mesma pasta e são importados no app em
# Camada de mercado → Prospecção rural → 🏛️ Áreas regularizadas → 📥 Importar arquivo.
import os
from qgis.core import (QgsVectorLayer, QgsVectorFileWriter, QgsCoordinateReferenceSystem,
                       QgsCoordinateTransformContext, QgsRectangle, QgsProject, QgsFeatureRequest)

UF = "ma"                                   # estado
RECORTE = (-46.2, -3.3, -44.4, -1.9)        # lon_min, lat_min, lon_max, lat_max — Baixada Maranhense / Pinheiro (+50 km). Use None para o estado todo
PASTA = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.path.expanduser("~/Documents/AquaNictemeral/10_sigef_incra")
BASE = "https://acervofundiario.incra.gov.br/i3geo/ogc.php?tema="
CAMADAS = {
    "sigef_particular": f"certificada_sigef_particular_{UF}",
    "sigef_publico":    f"certificada_sigef_publico_{UF}",
    "snci_privado":     f"imoveiscertificados_privado_{UF}",
    "snci_publico":     f"imoveiscertificados_publico_{UF}",
    "assentamentos":    f"assentamentos_{UF}",
}
# LGPD: estes campos de detentores NÃO são exportados
PESSOAIS = ("nome_deten", "nome_prop", "nome_titu", "nome_rt", "nome_resp", "cpf", "cnpj", "detentor", "proprietar", "titular", "requerente", "resp_tec")

crs = QgsCoordinateReferenceSystem("EPSG:4674")
for nome, tema in CAMADAS.items():
    uri = f"url='{BASE}{tema}' typename='{tema}' version='1.0.0' srsname='EPSG:4674' pagingEnabled='true' restrictToRequestBBOX='1'"
    lay = QgsVectorLayer(uri, nome, "WFS")
    if not lay.isValid():
        print(f"⚠️  {nome}: o servidor do INCRA não respondeu ({tema}). Tente de novo mais tarde.")
        continue
    req = QgsFeatureRequest()
    if RECORTE:
        req.setFilterRect(QgsRectangle(*RECORTE))
    campos = [i for i, f in enumerate(lay.fields()) if not f.name().lower().startswith(PESSOAIS)]
    opts = QgsVectorFileWriter.SaveVectorOptions()
    opts.driverName = "GeoJSON"; opts.fileEncoding = "UTF-8"; opts.attributes = campos
    if RECORTE:
        opts.filterExtent = QgsRectangle(*RECORTE)
    saida = os.path.join(PASTA, f"{nome}_{UF}.geojson")
    err = QgsVectorFileWriter.writeAsVectorFormatV3(lay, saida, QgsCoordinateTransformContext(), opts)
    n = sum(1 for _ in lay.getFeatures(req))
    print(f"✅ {nome}: {n} parcelas → {saida}" if err[0] == 0 else f"⚠️  {nome}: erro {err}")
    QgsProject.instance().addMapLayer(lay)
print("Pronto. Importe os .geojson no app (🏛️ Áreas regularizadas → 📥 Importar arquivo).")
