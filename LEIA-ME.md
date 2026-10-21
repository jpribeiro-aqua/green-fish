# RAS Multitanques — app para celular (PWA)

Esta pasta é o app pronto para ser hospedado num endereço próprio e instalado no celular, com ícone na tela inicial e funcionamento sem internet.

## O que tem aqui

| Arquivo | Para que serve |
|---|---|
| `index.html` | O app inteiro (todas as abas, login, projetos, usuários) |
| `config.js` | Onde entram o endereço e a chave do Supabase (login de verdade) |
| `manifest.webmanifest` | Nome, cores e ícones do app instalado |
| `sw.js` | Guarda o app no celular para abrir sem internet |
| `icons/` | Ícones do app |
| `supabase_setup.sql` | Script que cria o banco e as regras de acesso no Supabase |

## Dois modos de funcionamento

- **Demonstração** (como está agora, `config.js` em branco): login com usuário e senha guardados só no aparelho, com administrador local. Bom para ver e testar.
- **Conta do app** (com o Supabase configurado): login por e-mail e senha, "Esqueci a senha" por e-mail, projetos guardados na nuvem e abertos no celular ou no computador. A primeira conta criada vira administradora.

## Passo 1 — Publicar o app (GitHub Pages, gratuito)

1. Crie uma conta em <https://github.com> (pode usar o e-mail da UFMA).
2. Clique em **New repository**, dê o nome `ras-aqua`, marque **Public** e clique em **Create repository**.
3. Na página do repositório, clique em **uploading an existing file** e arraste **todo o conteúdo desta pasta** (incluindo a pasta `icons`). Clique em **Commit changes**.
4. Vá em **Settings > Pages**. Em *Branch*, escolha `main` e `/ (root)` e clique em **Save**.
5. Em 1 a 2 minutos o app fica no ar em `https://SEU-USUARIO.github.io/ras-aqua/`.

## Passo 2 — Instalar no celular

- **Android (Chrome):** abra o endereço, toque em **Mais > Instalar app** dentro do app (ou no menu ⋮ do Chrome > *Instalar app*).
- **iPhone (Safari):** abra o endereço, toque em **Compartilhar** > **Adicionar à Tela de Início**.

## Passo 3 — Login de verdade (Supabase, gratuito)

1. Crie uma conta em <https://supabase.com> e clique em **New project** (região: *South America (São Paulo)*).
2. No projeto, abra **SQL Editor > New query**, cole todo o conteúdo de `supabase_setup.sql` e clique em **Run**.
3. Em **Authentication > URL Configuration**, coloque em *Site URL* o endereço do app (`https://SEU-USUARIO.github.io/ras-aqua/`) e adicione o mesmo endereço em *Redirect URLs*.
4. Em **Project Settings > API**, copie o **Project URL** e a chave **anon public**.
5. Cole os dois em `config.js` (no GitHub: abra o arquivo, clique no lápis, edite e **Commit changes**).
6. Abra o app e **crie a sua conta primeiro**: ela vira a conta de administrador.

A chave *anon public* pode ficar no `config.js`: ela é pública por natureza, e quem protege os dados são as regras do `supabase_setup.sql` (cada pessoa só vê os próprios projetos; só o administrador aprova, suspende e cancela inscrições). **Nunca** coloque a chave *service_role* no app.

## Publicar uma versão nova

Substitua o `index.html` no GitHub e, no `sw.js`, aumente o número em `VERSAO` (por exemplo de `ras-v1` para `ras-v2`) para os celulares baixarem a versão nova.
