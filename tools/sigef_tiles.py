# Green Fish — gera a base INCRA (SIGEF + SNCI) por estado em blocos de 1 grau para o app.
# Uso: python sigef_tiles.py UF pasta_sigef pasta_snci pasta_saida
# Nao guarda dados pessoais: fica so codigo da parcela, nome da area, situacao, data, municipio (IBGE), area e contorno simplificado.
import sys,os,glob,json,math,re,collections,shapefile
def rdp(pts,eps):
    if len(pts)<3:return pts
    a,b=pts[0],pts[-1];dx,dy=b[0]-a[0],b[1]-a[1];L=dx*dx+dy*dy;mx=-1;ix=0
    for i in range(1,len(pts)-1):
        p=pts[i]
        if L==0:d=(p[0]-a[0])**2+(p[1]-a[1])**2
        else:
            t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/L));d=(p[0]-a[0]-t*dx)**2+(p[1]-a[1]-t*dy)**2
        if d>mx:mx=d;ix=i
    if mx>eps*eps:return rdp(pts[:ix+1],eps)[:-1]+rdp(pts[ix:],eps)
    return [a,b]
def simp(r,n=16):
    if len(r)>4000:r=r[::len(r)//4000+1]+[r[-1]]
    eps=1e-5;out=rdp(r,eps)
    while len(out)>n:eps*=1.8;out=rdp(r,eps)
    return out
def area_ha(r):
    la0=math.radians(sum(p[1] for p in r)/len(r));R=6371008.8;s=0;c=math.cos(la0)
    for i in range(len(r)):
        x1,y1=r[i-1];x2,y2=r[i];s+=math.radians(x1)*c*R*math.radians(y2)*R-math.radians(x2)*c*R*math.radians(y1)*R
    return abs(s/2)/1e4
ASS=re.compile(r"^(P\.?\s?A\.?\s?E?|P\.?\s?D\.?\s?S|PAF|PCA|PAC|PRB|PE)[\s\-\.]|ASSENTAMENTO|QUILOMB",re.I)
def conv(fase,sh,d):
    if not sh.points:return None
    parts=list(sh.parts)+[len(sh.points)];best=None;ba=-1;tot=0
    for i in range(len(sh.parts)):
        r=[(p[0],p[1]) for p in sh.points[parts[i]:parts[i+1]]]
        if len(r)<3:continue
        a=area_ha(r);tot+=a
        if a>ba:ba=a;best=r
    if not best:return None
    s=simp(best);lon=sum(p[0] for p in s)/len(s);lat=sum(p[1] for p in s)/len(s)
    flat=[];[flat.extend((round(p[1],5),round(p[0],5))) for p in s[:-1]]
    k=f"{math.floor(lat)}_{math.floor(lon)}"
    if fase=="sigef":
        nm=(d.get("nome_area") or "").strip();t="asent" if ASS.search(nm) else "sigef"
        return k,[t,d.get("parcela_co") or "",nm[:60],(d.get("situacao_i") or "").replace("_"," ").title()+" · cód. imóvel "+str(d.get("codigo_imo") or ""),str(d.get("data_aprov") or "")[:10],str(d.get("municipio_") or ""),round(tot,2),flat]
    try:h=float(d.get("qtd_area_p"))
    except Exception:h=None
    return k,["snci",str(d.get("num_certif") or ""),(d.get("nome_imove") or "")[:60],"Certificado SNCI · cód. imóvel "+str(d.get("cod_imovel") or ""),str(d.get("data_certi") or "")[:10],"",h,flat]
uf,ds,dn,out=sys.argv[1].lower(),sys.argv[2],sys.argv[3],sys.argv[4]
os.makedirs(out,exist_ok=True);tiles=collections.defaultdict(list);cnt=collections.Counter();falhas=[]
for fase,d in (("sigef",ds),("snci",dn)):
    shp=glob.glob(os.path.join(d,"**","*.shp"),recursive=True)
    if not shp:falhas.append(fase);continue
    r=shapefile.Reader(shp[0],encoding="latin1")
    for k in range(len(r)):
        try:
            x=conv(fase,r.shape(k),r.record(k).as_dict())
            if x:tiles[x[0]].append(x[1]);cnt[x[1][0]]+=1
        except Exception:pass
idx={"uf":uf.upper(),"fonte":"INCRA — SIGEF e SNCI (cópia Forest-GIS de out/2026)","data":"2026-10-16","n":dict(cnt),"tiles":{},"faltou":falhas}
for k,v in tiles.items():
    open(f"{out}/{uf}_{k}.json","w").write(json.dumps(v,ensure_ascii=False,separators=(",",":")));idx["tiles"][k]=len(v)
if tiles:open(f"{out}/{uf}_index.json","w").write(json.dumps(idx,ensure_ascii=False))
print(uf.upper(),dict(cnt),len(tiles),"blocos","faltou:",falhas)
