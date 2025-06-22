#!/usr/bin/env bash

# Trabalho Final de Administração de Sistemas (DS010)
# Script interativo para backup de pastas usando rsync e dialog
# Universidade Federal do Paraná (UFPR)
# 
# Autor: Gabriel Campos de Albuquerque
# Data: 19/06/2025
# Prof.: Dr. Mauro Castro
#
# VISÃO GERAL:
# Este script fornece uma interface gráfica em modo texto (TUI) para seleção
# de múltiplas pastas e execução de backup usando rsync. Utiliza o comando
# 'dialog' para criar menus interativos e oferece diferentes métodos de
# seleção de diretórios (navegação manual, fuzzy search, multi-seleção).
#
# FLUXO PRINCIPAL:
# 1. Verificação de dependências
# 2. Seleção interativa de pastas de origem
# 3. Definição do diretório de destino
# 4. Confirmação e execução do backup
# 5. Geração de logs e relatórios

# Configurações rigorosas de shell para evitar erros silenciosos
# -u: trata variáveis não definidas como erro
# -o pipefail: falha em qualquer comando de um pipeline que falhe
set -uo pipefail

# -------------------------------------------------------------------
# Variáveis globais do estado da aplicação
# -------------------------------------------------------------------

# Array que armazena os caminhos completos das pastas selecionadas
# Inicializado vazio e populado durante a interação do usuário
SELECTED_SOURCES=()

# String que armazena o caminho do diretório de destino
# Definido durante a fase de configuração do backup
DESTINATION=""

# -------------------------------------------------------------------
# Verificação de dependências do sistema
# -------------------------------------------------------------------
# Garante que todos os comandos necessários estão instalados antes
# de prosseguir com a execução do script
check_dependencies() {
  # Lista de comandos essenciais para o funcionamento do script
  for cmd in rsync dialog; do
    # command -v verifica se o comando existe no PATH
    # &>/dev/null redireciona toda saída para /dev/null (suprime output)
    if ! command -v "$cmd" &>/dev/null; then
      # >&2 redireciona para stderr (saída de erro padrão)
      echo "Erro: comando '$cmd' não encontrado." >&2
      exit 1
    fi
  done
}

# -------------------------------------------------------------------
# Visualização do conteúdo de diretórios
# -------------------------------------------------------------------
# Cria uma janela de preview mostrando o conteúdo de um diretório
# usando 'ls -la' em uma interface dialog
preview_directory() {
  local dir="$1"  # Recebe o caminho do diretório como parâmetro
  local tmp       # Declara variável local para arquivo temporário
  
  # mktemp cria um arquivo temporário único e retorna seu caminho
  tmp=$(mktemp)
  
  # Lista o conteúdo do diretório com detalhes
  # --color=never: desabilita cores para compatibilidade com dialog
  # 2>&1: redireciona stderr para stdout para capturar erros também
  # ||: operador de fallback - executa o comando à direita se o da esquerda falhar
  ls -la --color=never "$dir" > "$tmp" 2>&1 || echo "Erro ao listar $dir" >> "$tmp"
  
  # Exibe o conteúdo em uma janela dialog
  # --textbox: modo de visualização de arquivo texto
  # 0 0: dimensões automáticas (altura e largura)
  dialog --title "Conteúdo: $dir" --ok-label "OK" \
         --textbox "$tmp" 0 0
  
  # Remove o arquivo temporário para limpeza
  # -f: força remoção sem confirmação, não falha se arquivo não existir
  rm -f "$tmp"
}

# -------------------------------------------------------------------
# Navegação interativa de diretórios usando dialog --dselect
# -------------------------------------------------------------------
# Permite ao usuário navegar pelo sistema de arquivos e selecionar
# diretórios um por vez, adicionando-os à lista global SELECTED_SOURCES
nav_select() {
  # Variável local que mantém o diretório atual da navegação
  local cwd="$HOME" dir code
  
  # Loop infinito para navegação contínua até o usuário cancelar
  while true; do
    # --dselect: modo de seleção de diretório interativo
    # --stdout: output vai para stdout em vez de stderr
    # 15 60: altura e largura da janela
    dir=$(dialog --stdout --title "Navegação de Pastas" \
                 --ok-label "Selecionar" --cancel-label "Voltar" \
                 --dselect "$cwd/" 15 60)
    
    # Captura o código de saída do dialog
    code=$?
    
    # Se código diferente de 0, usuário cancelou ou houve erro
    [[ $code -ne 0 ]] && return 0  # Retorna ao menu principal
    
    # Valida se o caminho selecionado é realmente um diretório
    if [[ ! -d "$dir" ]]; then
      dialog --msgbox "Pasta inválida: $dir" 6 50
      continue  # Volta ao início do loop
    fi
    
    # Verifica duplicatas na lista de selecionados
    # Importante para evitar backups redundantes
    local exists=false
    for existing in "${SELECTED_SOURCES[@]}"; do
      if [[ "$existing" == "$dir" ]]; then
        exists=true
        break  # Sai do loop assim que encontra duplicata
      fi
    done
    
    # Se já existe, informa ao usuário e continua
    if $exists; then
      dialog --msgbox "Pasta já selecionada: $dir" 6 50
      continue
    fi
    
    # Adiciona ao array de fontes selecionadas
    # += funciona para append em arrays bash
    SELECTED_SOURCES+=("$dir")
    dialog --msgbox "Adicionado: $dir" 5 40
    
    # Oferece preview opcional do diretório selecionado
    # --yesno: caixa de diálogo com botões Sim/Não
    if dialog --yes-label "Sim" --no-label "Não" --yesno "Mostrar conteúdo de $dir?" 6 50; then
      preview_directory "$dir"
    fi
    
    # Pergunta se usuário quer continuar adicionando mais pastas
    if ! dialog --yes-label "Sim" --no-label "Não" --yesno "Adicionar mais pastas?" 6 40; then
      break  # Sai do loop principal se usuário não quer continuar
    fi
    
    # Define novo ponto de partida para próxima navegação
    # Melhora UX mantendo contexto da navegação anterior
    cwd="$dir"
  done
}

# -------------------------------------------------------------------
# Seleção usando fuzzy finder (fzf) - método avançado de busca
# -------------------------------------------------------------------
# Utiliza fzf para busca interativa e seleção múltipla de diretórios
fuzzy_select() {
  # Verifica se fzf está disponível no sistema
  if ! command -v fzf &>/dev/null; then
    dialog --msgbox "fzf não instalado. Instale com: apt install fzf" 6 60
    return  # Retorna sem fazer nada se fzf não estiver disponível
  fi
  
  local sel  # Variável para armazenar seleções do fzf
  
  # find: busca diretórios recursivamente
  # -maxdepth 4: limita profundidade para melhor performance
  # -type d: apenas diretórios
  # 2>/dev/null: suprime mensagens de erro (ex: permissões)
  # fzf --multi: permite seleção múltipla
  # --height 40%: ocupa 40% da altura do terminal
  # --border: adiciona bordas visuais
  sel=$(find "$HOME" -maxdepth 4 -type d 2>/dev/null | fzf --multi --height 40% --border --prompt="Selecione pastas: ")
  
  # Se usuário cancelou (ESC ou Ctrl+C), sel estará vazio
  if [[ -z "$sel" ]]; then
    return
  fi
  
  # Contador para informar quantas pastas foram adicionadas
  local added=0
  
  # Processa cada linha da seleção do fzf
  # IFS= preserva espaços em branco no início/fim
  # read -r evita interpretação de caracteres de escape
  while IFS= read -r d; do
    # Mesmo processo de verificação de duplicatas
    local exists=false
    for existing in "${SELECTED_SOURCES[@]}"; do
      if [[ "$existing" == "$d" ]]; then
        exists=true
        break
      fi
    done
    
    # Adiciona apenas se não for duplicata
    if ! $exists; then
      SELECTED_SOURCES+=("$d")
      ((added++))  # Incremento aritmético bash
    fi
  done <<< "$sel"  # Here-string: passa $sel como input para o while
  
  # Informa resultado da operação ao usuário
  dialog --msgbox "Adicionadas $added pastas via fuzzy search." 6 50
}

# -------------------------------------------------------------------
# Seleção múltipla de subpastas usando checklist
# -------------------------------------------------------------------
# Mostra subpastas de um diretório pai e permite seleção múltipla
# usando interface de checklist do dialog
nav_multi_select() {
  local parent  # Diretório pai para listar subpastas
  
  # Determina diretório pai baseado no contexto atual
  if (( ${#SELECTED_SOURCES[@]} == 0 )); then
    # Se nenhuma pasta foi selecionada, usa HOME como padrão
    parent="$HOME"
  else
    # Usa a última pasta selecionada como contexto
    # [-1] acessa último elemento do array
    parent="${SELECTED_SOURCES[-1]}"
  fi
  
  local subs sel code  # Arrays e variáveis para processamento
  
  # mapfile/readarray: lê output de comando em array
  # -t: remove newlines do final de cada elemento
  # find -maxdepth 1 -mindepth 1: apenas subpastas diretas (não recursivo)
  # sort: ordena alfabeticamente para melhor UX
  mapfile -t subs < <(find "$parent" -maxdepth 1 -mindepth 1 -type d | sort)
  
  # Verifica se existem subpastas para mostrar
  if [[ ${#subs[@]} -eq 0 ]]; then
    dialog --msgbox "Sem subpastas em $parent." 6 50
    return
  fi
  
  # Constrói array para o checklist do dialog
  # Formato: caminho_completo "nome_exibido" status_inicial
  local chk=()
  for d in "${subs[@]}"; do 
    # basename extrai apenas o nome da pasta (sem caminho completo)
    chk+=("$d" "$(basename "$d")" off)  # "off" = desmarcado inicialmente
  done
  
  # Exibe checklist para seleção múltipla
  # --checklist: permite marcar/desmarcar múltiplos itens
  # 15 70 10: altura, largura, altura_da_lista
  sel=$(dialog --stdout --title "Subpastas de $(basename "$parent")" \
               --ok-label "Adicionar" --cancel-label "Voltar" \
               --checklist "Marque as subpastas para backup:" 15 70 10 "${chk[@]}")
  code=$?
  
  # Se usuário cancelou, retorna sem fazer alterações
  [[ $code -ne 0 ]] && return
  
  # Se nada foi selecionado, retorna
  if [[ -z "$sel" ]]; then
    return
  fi
  
  # Parse do output do dialog (que vem com aspas)
  # eval é necessário pois dialog retorna strings com aspas
  local chosen=()
  eval "chosen=($sel)"
  
  # Processa cada item selecionado
  local added=0
  for c in "${chosen[@]}"; do
    # Verificação padrão de duplicatas
    local exists=false
    for existing in "${SELECTED_SOURCES[@]}"; do
      if [[ "$existing" == "$c" ]]; then
        exists=true
        break
      fi
    done
    
    # Adiciona se não for duplicata
    if ! $exists; then
      SELECTED_SOURCES+=("$c")
      ((added++))
    fi
  done
  
  # Feedback para o usuário
  dialog --msgbox "Adicionadas $added subpastas." 6 50
}

# -------------------------------------------------------------------
# Remoção de pastas da lista de selecionadas
# -------------------------------------------------------------------
# Permite ao usuário remover itens da lista SELECTED_SOURCES
# usando interface de checklist
remove_sources() {
  # Verifica se há algo para remover
  if (( ${#SELECTED_SOURCES[@]} == 0 )); then
    dialog --msgbox "Nenhuma pasta para remover." 5 40
    return
  fi
  
  local chk=() sel code  # Arrays para construir checklist
  
  # Constrói lista de opções para remoção
  for d in "${SELECTED_SOURCES[@]}"; do 
    chk+=("$d" "$(basename "$d")" off)  # Mostra apenas nome da pasta
  done
  
  # Interface de seleção para remoção
  sel=$(dialog --stdout --title "Remover Pastas" \
               --ok-label "Remover" --cancel-label "Voltar" \
               --checklist "Selecione as pastas a remover:" 15 70 10 "${chk[@]}")
  code=$?
  
  # Se cancelou, não faz nada
  [[ $code -ne 0 ]] && return
  
  # Se nada foi selecionado, retorna
  if [[ -z "$sel" ]]; then
    return
  fi
  
  # Parse das seleções para remoção
  local to_remove=()
  eval "to_remove=($sel)"
  
  # Reconstrói array excluindo itens marcados para remoção
  # Estratégia: cria novo array apenas com itens não marcados
  local new=()
  for d in "${SELECTED_SOURCES[@]}"; do
    local keep=true  # Assume que deve manter por padrão
    
    # Verifica se este item está na lista de remoção
    for r in "${to_remove[@]}"; do 
      if [[ "$d" == "$r" ]]; then
        keep=false  # Marca para não manter
        break
      fi
    done
    
    # Adiciona ao novo array apenas se deve manter
    $keep && new+=("$d")
  done
  
  # Substitui array global pelo novo array filtrado
  SELECTED_SOURCES=("${new[@]}")
  
  # Feedback da operação
  dialog --msgbox "Removidas ${#to_remove[@]} pastas." 6 50
}

# -------------------------------------------------------------------
# Visualização da lista atual de pastas selecionadas
# -------------------------------------------------------------------
# Cria um relatório formatado das pastas selecionadas para review
view_selected() {
  # Verifica se há algo para mostrar
  if (( ${#SELECTED_SOURCES[@]} == 0 )); then
    dialog --msgbox "Nenhuma pasta selecionada." 5 40
    return
  fi
  
  local tmp  # Arquivo temporário para o relatório
  tmp=$(mktemp)
  
  # Constrói relatório formatado
  echo "PASTAS SELECIONADAS PARA BACKUP:" >> "$tmp"
  echo "=================================" >> "$tmp"
  echo "" >> "$tmp"  # Linha em branco para espaçamento
  
  # Lista numerada de todas as pastas selecionadas
  local i=1
  for d in "${SELECTED_SOURCES[@]}"; do 
    echo "$i. $d" >> "$tmp"  # Caminho completo
    ((i++))  # Incrementa contador
  done
  
  # Adiciona estatísticas ao final
  echo "" >> "$tmp"
  echo "Total: ${#SELECTED_SOURCES[@]} pastas" >> "$tmp"
  
  # Exibe relatório em janela textbox
  # Título inclui contagem para referência rápida
  dialog --title "Pastas Selecionadas (${#SELECTED_SOURCES[@]})" \
         --ok-label "OK" \
         --textbox "$tmp" 0 0
  
  # Limpeza do arquivo temporário
  rm -f "$tmp"
}

# -------------------------------------------------------------------
# Menu principal de seleção de fontes
# -------------------------------------------------------------------
# Loop principal que coordena todas as operações de seleção de pastas
# Apresenta menu com opções e delega para funções específicas
select_sources() {
  # Loop infinito até usuário escolher prosseguir ou sair
  while true; do
    # Informação dinâmica sobre estado atual
    local info="Status: ${#SELECTED_SOURCES[@]} pastas selecionadas\n\n"
    
    local choice code  # Variáveis para capturar seleção do usuário
    
    # Menu principal com todas as opções disponíveis
    # Altura e largura calculadas para acomodar todas as opções
    choice=$(dialog --stdout --title "Menu de Seleção de Pastas" \
                    --cancel-label "Sair" \
                    --menu "${info}Escolha uma ação:" 18 70 7 \
      1 "Navegar e selecionar pasta" \
      2 "Pesquisa fuzzy (fzf)" \
      3 "Adicionar subpastas" \
      4 "Remover pastas selecionadas" \
      5 "Ver lista de selecionadas" \
      6 "Limpar todas as seleções" \
      7 "Prosseguir para backup")
    code=$?
    
    # Tratamento de cancelamento com confirmação
    if [[ $code -ne 0 ]]; then
      # Confirma antes de sair para evitar perda acidental de trabalho
      if dialog --yes-label "Sim" --no-label "Não" --yesno "Deseja sair do programa?" 6 40; then
        exit 0
      else
        continue  # Volta ao menu se não confirmar saída
      fi
    fi
    
    # Dispatcher para funções baseado na escolha do usuário
    case $choice in
      1) nav_select ;;          # Navegação manual
      2) fuzzy_select ;;        # Busca com fzf
      3) nav_multi_select ;;    # Seleção múltipla de subpastas
      4) remove_sources ;;      # Remoção de itens
      5) view_selected ;;       # Visualização da lista
      6) 
        # Operação destrutiva - requer confirmação
        if dialog --yes-label "Sim" --no-label "Não" --yesno "Limpar todas as ${#SELECTED_SOURCES[@]} pastas selecionadas?" 6 50; then
          SELECTED_SOURCES=()  # Limpa array global
          dialog --msgbox "Todas as seleções foram removidas." 5 40
        fi
        ;;
      7) 
        # Validação antes de prosseguir
        if (( ${#SELECTED_SOURCES[@]} == 0 )); then
          dialog --msgbox "Selecione pelo menos uma pasta antes de prosseguir." 6 50
        else
          break  # Sai do loop para continuar com backup
        fi
        ;;  
    esac
  done
}

# -------------------------------------------------------------------
# Seleção e validação do diretório de destino
# -------------------------------------------------------------------
# Gerencia a definição do diretório onde o backup será armazenado
# Inclui validação de permissões e criação automática se necessário
select_destination() {
  local dir code  # Variáveis para input e controle
  
  # Loop até obter destino válido ou usuário cancelar
  while true; do
    # Input box com valor padrão sugerido
    dir=$(dialog --stdout --title "Destino do Backup" \
                 --cancel-label "Cancelar" \
                 --inputbox "Digite o diretório de destino:" 8 60 "$HOME/backup")
    code=$?
    
    # Tratamento de cancelamento
    if [[ $code -ne 0 ]]; then
      if dialog --yes-label "Sim" --no-label "Não" --yesno "Cancelar operação de backup?" 6 40; then
        exit 0
      else
        continue  # Volta a pedir destino
      fi
    fi
    
    # Normalização: remove barra final se existir
    # Importante para consistência nos caminhos
    dir="${dir%/}"
    
    # Validação básica: não pode estar vazio
    if [[ -z "$dir" ]]; then
      dialog --msgbox "Diretório não pode estar vazio." 6 40
      continue
    fi
    
    # Se diretório não existe, oferece criação automática
    if [[ ! -d "$dir" ]]; then
      if dialog --yes-label "Sim" --no-label "Não" --yesno "Diretório '$dir' não existe.\nDeseja criar?" 7 60; then
        # mkdir -p: cria diretórios pais se necessário
        # 2>/dev/null: suprime mensagens de erro
        if mkdir -p "$dir" 2>/dev/null; then
          dialog --msgbox "Diretório criado com sucesso." 5 40
        else
          # Falha na criação - provavelmente permissões
          dialog --msgbox "Erro ao criar diretório. Verifique as permissões." 6 60
          continue
        fi
      else
        continue  # Usuário não quer criar, volta a pedir
      fi
    fi
    
    # Verificação crucial: permissão de escrita
    # -w testa se o usuário atual pode escrever no diretório
    if [[ ! -w "$dir" ]]; then
      dialog --msgbox "Sem permissão de escrita em '$dir'." 6 50
      continue
    fi
    
    # Se chegou até aqui, destino é válido
    DESTINATION="$dir"
    break
  done
}

# -------------------------------------------------------------------
# Execução do backup propriamente dito
# -------------------------------------------------------------------
# Coordena a execução do rsync para todas as pastas selecionadas
# Gera logs detalhados e relatórios de progresso
perform_backup() {
  # Timestamp único para arquivos de log
  # Formato: AAAAMMDD_HHMMSS para ordenação cronológica
  local timestamp=$(date +%Y%m%d_%H%M%S)
  local log="$DESTINATION/backup_$timestamp.log"
  local summary="$DESTINATION/backup_summary_$timestamp.txt"
  
  # Cria arquivo de resumo executivo do backup
  # Useful para auditorias e troubleshooting posterior
  {
    echo "RESUMO DO BACKUP - $(date)"
    echo "================================="
    echo ""
    echo "Destino: $DESTINATION"
    echo "Total de pastas: ${#SELECTED_SOURCES[@]}"
    echo ""
    echo "Pastas incluídas:"
    # Lista todas as pastas que serão processadas
    for src in "${SELECTED_SOURCES[@]}"; do
      echo "  - $src"
    done
    echo ""
    echo "Log detalhado: $log"
    echo ""
  } > "$summary"
  
  # Inicialização de contadores para barra de progresso
  local total=${#SELECTED_SOURCES[@]}
  local current=0
  
  # Loop principal de backup - processa cada pasta selecionada
  for src in "${SELECTED_SOURCES[@]}"; do
    ((current++))  # Incrementa contador de progresso
    
    # Define nome da pasta destino baseado no nome da pasta origem
    # basename extrai apenas o nome final do caminho
    local dest_folder="$DESTINATION/$(basename "$src")"
    
    # Atualização da barra de progresso usando protocolo XXX do dialog
    # Este formato específico é requerido pelo --gauge
    echo "XXX"
    echo $((current * 100 / total))  # Calcula percentual
    echo "Fazendo backup de $(basename "$src")... ($current/$total)"
    echo "XXX"
    
    # Execução do rsync com opções otimizadas
    # -a: modo arquivo (preserva permissões, timestamps, etc)
    # -v: verbose (detalhado)
    # -h: human-readable (tamanhos legíveis)
    # --delete: remove arquivos no destino que não existem na origem
    # --exclude: ignora arquivos temporários e do sistema
    # --log-file: registra atividade detalhada
    # "$src/": barra final importante - sincroniza CONTEÚDO da pasta
    # 2>>: redireciona erros para o arquivo de log (append)
    if rsync -avh --delete --exclude='.DS_Store' --exclude='*.tmp' \
             --log-file="$log" "$src/" "$dest_folder/" 2>>"$log"; then
      echo "✓ Sucesso: $src -> $dest_folder" >> "$summary"
    else
      echo "✗ Erro: $src -> $dest_folder" >> "$summary"
    fi
    
    # Pequena pausa para permitir visualização do progresso
    # Em backups reais, esta linha pode ser removida
    sleep 0.5
    
  # Pipeline para dialog --gauge
  # Todo o output do loop é direcionado para a barra de progresso
  done | dialog --title "Executando Backup" --gauge "Preparando..." 8 60 0
  
  # Finaliza relatório de resumo
  echo "" >> "$summary"
  echo "Backup finalizado em: $(date)" >> "$summary"
  
  # Mostra resultado final ao usuário
  dialog --title "Backup Concluído" --textbox "$summary" 0 0
  
  # Oferece visualização do log detalhado (opcional)
  # Útil para troubleshooting ou verificação de detalhes
  if dialog --yes-label "Sim" --no-label "Não" --yesno "Deseja ver o log detalhado?" 6 40; then
    dialog --title "Log Detalhado" --textbox "$log" 0 0
  fi
}

# -------------------------------------------------------------------
# Função principal - orquestra todo o fluxo da aplicação
# -------------------------------------------------------------------
# Coordena a execução sequencial de todas as fases do backup
main() {
  # Fase 1: Verificações iniciais
  check_dependencies
  
  # Fase 2: Apresentação e orientação inicial
  dialog --title "Backup Interativo" \
         --msgbox "Bem-vindo ao sistema de backup interativo!\n\nEste script ajudará você a selecionar pastas e fazer backup usando rsync." 8 60
  
  # Fase 3: Seleção de pastas de origem
  select_sources
  
  # Validação de segurança: garante que algo foi selecionado
  if (( ${#SELECTED_SOURCES[@]} == 0 )); then
    dialog --msgbox "Nenhuma pasta selecionada. Saindo..." 5 40
    exit 0
  fi
  
  # Fase 4: Definição do destino
  select_destination
  
  # Fase 5: Confirmação final com resumo completo
  local tmp
  tmp=$(mktemp)
  {
    echo "CONFIRMAÇÃO DO BACKUP"
    echo "===================="
    echo ""
    echo "Pastas de origem (${#SELECTED_SOURCES[@]}):"
    for src in "${SELECTED_SOURCES[@]}"; do
      echo "  • $src"
    done
    echo ""
    echo "Destino: $DESTINATION"
    echo ""
    echo "Pressione OK para continuar ou Cancelar para voltar."
  } > "$tmp"
  
  # Última chance de cancelar antes da execução
  if dialog --title "Confirmar Backup" --ok-label "Executar Backup" \
            --cancel-label "Cancelar" --textbox "$tmp" 0 0; then
    # Fase 6: Execução do backup
    perform_backup
  else
    dialog --msgbox "Backup cancelado pelo usuário." 5 40
  fi
  
  # Limpeza final
  rm -f "$tmp"
  clear  # Limpa tela ao finalizar
  echo "Script finalizado. Obrigado por usar o backup interativo!"
}

# -------------------------------------------------------------------
# Ponto de entrada do script
# -------------------------------------------------------------------
# "$@" passa todos os argumentos da linha de comando para main()
# Permite extensibilidade futura se necessário adicionar parâmetros
main "$@"