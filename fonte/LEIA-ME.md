# Green Fish · código-fonte

Programe o app por aqui, no VS Code. O `index.html` da pasta de cima é o resultado final: ele é montado a partir desta pasta. Não edite o `index.html` direto, porque a próxima montagem apaga o que foi mudado nele.

## Os arquivos

| Arquivo | O que tem |
|---|---|
| `fonte/app.html` | O app inteiro: abas, Calculadora, Levantamentos, desenho técnico 2D/3D, mapas, Painel, Financeiro, AquaGestão… |
| `fonte/aquanictemeral.html` | A aba AquaNictemeral (água, tanques T1…Tn, correlações, coluna 🧭). Vai embutida no app, no lugar de `__AQUANICTEMERAL__`. |
| `fonte/montar.py` | Junta os dois e gera o `index.html` (e, se pedir, a cópia `Sistema_RAS_Multitanques.html`). |
| `sw.js` | Guarda o app no aparelho. A linha `const VERSAO = "ras-v185";` é a versão: cada publicação precisa de um número novo. |
| `config.js` | Endereço e chave pública (anon) do Supabase. |
| `fonte/vscode/` | Configuração do VS Code: tarefas de montar, extensões recomendadas e ajustes. |

## Preparar o VS Code (uma vez só)

1. No Finder, abra a pasta `green-fish` e aperte ⇧⌘. (Shift + Command + ponto) para ver as pastas ocultas.
2. Copie a pasta `fonte/vscode` para dentro da `green-fish` e renomeie a cópia para `.vscode` (com ponto na frente). Se já houver uma pasta `.vscode` vazia, coloque os 3 arquivos dentro dela.
3. Abra a pasta `green-fish` no VS Code. Ele vai oferecer instalar as extensões recomendadas (Live Server, Python): aceite.

Isso cria os botões em Terminal › Executar Tarefa…. Sem eles, tudo funciona do mesmo jeito pelo comando `python3 fonte/montar.py --nova`.

## Passo a passo de uma mudança

1. **Abra a pasta** `green-fish` no VS Code (Arquivo › Abrir Pasta…). Se ele perguntar se confia nos autores, escolha **Sim, confio**.
2. **Edite** `fonte/app.html` ou `fonte/aquanictemeral.html` e salve (⌘S).
3. **Monte o app**, de um destes jeitos:
   - **Dois cliques em `Montar app.command`** (na pasta green-fish, pelo Finder) → escolha 1 (nova versão).
   - VS Code › Terminal › Executar Tarefa… › **Montar app (nova versão)** (depois de copiar `fonte/vscode` para `.vscode`).
   - Também dá pelo Terminal do VS Code, na pasta green-fish: `python3 fonte/montar.py --nova`
   - Na primeira vez, o Mac pode pedir para instalar as "Ferramentas de linha de comando" (traz o python3). Aceite.
4. **Teste no navegador**: clique com o botão direito no `index.html` › **Open with Live Server** (extensão recomendada). Cada vez que você montar de novo, a página recarrega.
5. **Publique**: no GitHub Desktop, escreva um resumo › **Commit to main** › **Push origin**. Em ~2 minutos o site atualiza, e o app dos aparelhos se atualiza sozinho ao abrir.

Se algo der errado, o GitHub Desktop mostra cada mudança (aba History) e permite desfazer.

## Onde fica cada parte

Use ⌘F (no arquivo) ou ⇧⌘F (na pasta toda) e procure pelo texto da coluna "Procure por".

### `fonte/app.html`

| Parte do app | Procure por |
|---|---|
| Troca de abas | `function setView(` |
| Calculadora (parâmetros do projeto, projeto rápido) | `v145: Calculadora · projeto de viveiros` · `const D0=` · `v172: projeto rápido` |
| Arquivo de projetos / desenhos salvos | `window.vvDesenhos=` · `window.vvDesenhoUI=` |
| Desenho técnico 2D (planta e corte) | `function gfCAD(q)` |
| Equipamentos (aeradores, coleta, comportas) | `function gfEquip0(` |
| Desenho 3D | `v165: desenho técnico em 3D` · `function gf3DView(` |
| Vista "Todos juntos" | `v168: vista "Conjunto"` |
| Exportar DXF / GeoJSON / KML | `v177: exportar o desenho` |
| Editar o desenho (2D, 3D, tela cheia) | `v178: editar o desenho à mão` |
| Quadro do desenho (botões 2D/3D, Ampliar, Exportar) | `function gfCADInto(` |
| Mapa ao vivo | `mapa do projeto em tempo real` |
| Importar arquivos (PNG, PDF, Excel, Word, DXF, KML…) | `async function processar(` |
| Levantamentos (topografia) | `window.topoGeo=` · `id="tab-topo"` |
| Análise de dados e correlação entre abas | `v144: Análise de dados` |
| AquaGestão | `v141: aba AquaGestão` |
| Financeiro | `v134: aba Financeiro` |
| Atualização automática do app | `const APP_VERSAO=` · `function forcaAtualizar` |
| Estilos (cores, tamanhos) | `<style>` (há vários blocos; procure pela classe, ex.: `.gfc-ed`) |

### `fonte/aquanictemeral.html`

| Parte | Procure por |
|---|---|
| Filtro por tanque (T1, T2…) | `const passa =` · `const selIds =` |
| Identificação dos tanques, Correlacionar, Ligar leituras | `function renderIds(` |
| Gráficos de correlação | `v180: correlação entre tanques` |
| Coluna 🧭 ordem do processamento | `v184: coluna "AquaNictemeral` · `function fxIr(` |
| Importação de leituras | `window.aquaImport =` |
| Avaliação pelas faixas da espécie | `function avaliar(` |
| Dados que vão para as outras abas | `window.aquaRelatorio =` · `window.aquaResumo =` |

## Trabalhando junto com o Claude

O Claude também edita estes mesmos arquivos. Antes de pedir uma mudança, **salve e faça Commit** do que você mudou. Assim ele parte da sua versão, e nada se perde.
