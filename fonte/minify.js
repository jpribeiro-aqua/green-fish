/* Green Fish — embaralha (minifica) os <script> do index.html publicado.
   Uso: node fonte/minify.js <entrada.html> <saida.html>
   Mantém o código-fonte legível em fonte/app.html; só o arquivo publicado sai embaralhado.
   Precisa de terser:  (na pasta do repositório)  npm install terser@5.36.0 --no-save */
const {minify}=require('terser');const fs=require('fs');
(async()=>{
 const src=process.argv[2],out=process.argv[3]||src;
 let s=fs.readFileSync(src,'utf8');
 const re=/<script(\b[^>]*)>([\s\S]*?)<\/script>/g;
 let m,parts=[],last=0,n=0,kept=0,errs=[];
 while((m=re.exec(s))){
  const attrs=m[1]||'',body=m[2];
  parts.push(s.slice(last,m.index));last=re.lastIndex;
  if(/\bsrc=/.test(attrs)||/type=("|')(?!text\/javascript|application\/javascript|module)/.test(attrs)||!body.trim()){parts.push(m[0]);kept++;continue;}
  try{const r=await minify(body,{compress:{},mangle:{toplevel:false},format:{comments:false}});
   if(r.code==null)throw new Error('vazio');parts.push('<script'+attrs+'>'+r.code+'</script>');n++;
  }catch(e){errs.push(e.message.slice(0,80));parts.push(m[0]);kept++;}
 }
 parts.push(s.slice(last));const res=parts.join('');fs.writeFileSync(out,res);
 console.log(`✓ ${out}: ${n} blocos embaralhados, ${kept} mantidos` + (errs.length?`, ${errs.length} erro(s): `+errs.slice(0,2).join(' | '):''));
 if(errs.length){process.exitCode=1;}
})();
