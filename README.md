# Trabalho Final de Administração de Sistemas (DS010)

### Universidade Federal do Paraná (UFPR)

### Autor: Gabriel Campos de Albuquerque

### Prof.: Dr. Mauro Castro

Projeto Final Disciplina de Adminsitracao de Sistemas - DS010 - UFPR

# Script de Backup Interativo

## Documentação Técnica Completa

---

## 1. Visão Geral

O **Script de Backup Interativo** é uma solução em Bash que permite aos usuários selecionar múltiplas pastas de forma intuitiva e realizar backups incrementais usando `rsync`. O script oferece interface baseada em terminal com navegação por menus, pesquisa fuzzy e geração automática de logs.

### 1.1 Características Principais

- Interface interativa com `dialog`
- Seleção múltipla de pastas de origem
- Navegação de diretórios visual
- Pesquisa fuzzy com `fzf` (opcional)
- Preview de conteúdo de pastas
- Backup incremental com `rsync`
- Geração automática de logs e relatórios
- Validação de dependências e permissões

---

## 2. Pré-requisitos e Dependências

### 2.1 Dependências Obrigatórias

```bash
# Instalar no Ubuntu/Debian
sudo apt update
sudo apt install rsync dialog

# Instalar no CentOS/RHEL
sudo yum install rsync dialog
```

### 2.2 Dependências Opcionais

```bash
# Para pesquisa fuzzy (recomendado)
sudo apt install fzf
```

### 2.3 Requisitos do Sistema

- Sistema operacional: Linux/Unix
- Shell: Bash 4.0+
- Espaço em disco: suficiente para backups
- Permissões: leitura nas origens, escrita no destino

---

## 3. Instalação e Configuração

### 3.1 Download e Preparação

```bash
# Baixar o script
git clone https://github.com/ocoiel/proj-final-ds010-ufpr-adm-sist.git

# Dar permissão de execução
chmod +x backup_interativo.bash

# Verificar dependências
./backup_interativo.bash
```

### 3.2 Estrutura de Arquivos

```
projeto_backup/
├── backup_interativo.bash    # Script principal
├── README.md                 # Documentação
└── logs/                     # Logs gerados (criado automaticamente)
```

---

## 4. Manual de Uso

### 4.1 Iniciando o Script

```bash
./backup_interativo.bash
```

### 4.2 Fluxo de Uso Completo

#### Etapa 1: Menu Principal

O script apresenta as seguintes opções:

1. **Navegar e selecionar pasta**: Navegação visual de diretórios
2. **Pesquisa fuzzy (fzf)**: Busca rápida por nome
3. **Adicionar subpastas**: Seleção múltipla de subdiretórios
4. **Remover pastas selecionadas**: Gestão das seleções
5. **Ver lista de selecionadas**: Visualização das escolhas
6. **Limpar todas as seleções**: Reset completo
7. **Prosseguir para backup**: Avançar para próxima etapa

#### Etapa 2: Seleção de Pastas

- **Navegação**: Use setas ↑↓ para navegar, Enter para selecionar
- **Preview**: Visualize conteúdo antes de confirmar
- **Validação**: Sistema impede seleções duplicadas

#### Etapa 3: Definição do Destino

- Digite caminho do backup (padrão: `$HOME/backup`)
- Script cria diretório se não existir
- Valida permissões de escrita

#### Etapa 4: Confirmação e Execução

- Revise todas as seleções
- Confirme para iniciar backup
- Acompanhe progresso em tempo real

### 4.3 Exemplos de Uso

#### Cenário 1: Backup de Documentos

```bash
# Pastas selecionadas:
/home/usuario/Documentos
/home/usuario/Projetos
/home/usuario/Scripts

# Destino:
/media/backup_externo/backup_documentos
```

#### Cenário 2: Backup de Configurações

```bash
# Usando fuzzy search para encontrar configs:
/home/usuario/.config
/home/usuario/.ssh
/etc/nginx

# Destino:
/backup/configs_sistema
```

---

## 5. Funcionalidades Detalhadas

### 5.1 Sistema de Navegação

- **dselect**: Interface gráfica para seleção de diretórios
- **Validação**: Verifica existência e permissões
- **Preview**: Mostra conteúdo com `ls -la`
- **Breadcrumb**: Mantém contexto da navegação

### 5.2 Pesquisa Fuzzy (fzf)

```bash
# Busca em até 4 níveis de profundidade
find "$HOME" -maxdepth 4 -type d | fzf --multi
```

- Seleção múltipla com Tab
- Busca por nome parcial
- Performance otimizada

### 5.3 Gestão de Seleções

- **Anti-duplicação**: Previne pastas repetidas
- **Remoção seletiva**: Interface de checklist
- **Visualização**: Lista formatada das escolhas
- **Reset**: Limpeza completa das seleções

### 5.4 Sistema de Backup

```bash
rsync -avh --delete --exclude='.DS_Store' --exclude='*.tmp' \
      --log-file="$log" "$src/" "$dest_folder/"
```

**Parâmetros do rsync:**

- `-a`: Modo arquivo (preserva atributos)
- `-v`: Verbose (mostra progresso)
- `-h`: Human-readable (tamanhos legíveis)
- `--delete`: Remove arquivos obsoletos no destino
- `--exclude`: Ignora arquivos temporários
- `--log-file`: Gera log detalhado

---

## 6. Arquivos de Log e Relatórios

### 6.1 Estrutura dos Logs

```
backup_20241219_143052.log           # Log detalhado do rsync
backup_summary_20241219_143052.txt   # Resumo executivo
```

### 6.2 Conteúdo do Resumo

```
RESUMO DO BACKUP - Thu Dec 19 14:30:52 2024
=================================

Destino: /home/backup
Total de pastas: 3

Pastas incluídas:
  - /home/usuario/Documentos
  - /home/usuario/Projetos
  - /home/usuario/Scripts

Log detalhado: backup_20241219_143052.log

✓ Sucesso: /home/usuario/Documentos -> /home/backup/Documentos
✓ Sucesso: /home/usuario/Projetos -> /home/backup/Projetos
✓ Sucesso: /home/usuario/Scripts -> /home/backup/Scripts

Backup finalizado em: Thu Dec 19 14:32:15 2024
```

---

## 7. Tratamento de Erros

### 7.1 Validações Implementadas

- **Dependências**: Verifica `rsync` e `dialog`
- **Permissões**: Valida leitura/escrita
- **Caminhos**: Confirma existência de diretórios
- **Espaço**: rsync falha graciosamente se sem espaço

### 7.2 Códigos de Saída

- `0`: Sucesso completo
- `1`: Erro de dependências
- `2`: Cancelamento pelo usuário
- `>2`: Erros do rsync

### 7.3 Recuperação de Erros

- **Pastas inválidas**: Permite nova seleção
- **Destino inválido**: Loop até corrigir
- **Falha de backup**: Continua com próximas pastas

---

## 8. Arquitetura do Código

### 8.1 Estrutura Modular

```bash
main()                    # Função principal
├── check_dependencies()  # Validação inicial
├── select_sources()      # Loop de seleção
│   ├── nav_select()      # Navegação dselect
│   ├── fuzzy_select()    # Pesquisa fzf
│   ├── nav_multi_select() # Subpastas
│   ├── remove_sources()  # Remoção
│   └── view_selected()   # Visualização
├── select_destination()  # Escolha destino
└── perform_backup()      # Execução rsync
```

### 8.2 Variáveis Globais

```bash
SELECTED_SOURCES=()  # Array de pastas selecionadas
DESTINATION=""       # Diretório de destino
```

### 8.3 Convenções de Código

- Funções com nomes descritivos
- Validação em cada entrada de usuário
- Cleanup automático de arquivos temporários
- Comentários explicativos

---

## 9. Testes e Validação

### 9.1 Cenários de Teste

| Cenário               | Entrada              | Resultado Esperado          |
| --------------------- | -------------------- | --------------------------- |
| Dependências ausentes | Sistema sem `dialog` | Erro e saída                |
| Pasta inexistente     | `/pasta/falsa`       | Mensagem de erro            |
| Destino sem permissão | `/root/backup`       | Solicitação de novo destino |
| Backup bem-sucedido   | Pastas válidas       | Logs gerados                |
| Cancelamento          | ESC no menu          | Retorno ao menu anterior    |

### 9.2 Testes de Integração

```bash
# Teste básico
./backup_interativo.bash

# Teste sem fzf
sudo apt remove fzf
./backup_interativo.bash

# Teste com pastas grandes
# (criar estrutura de teste)
```

---

## 10. Troubleshooting

### 10.1 Problemas Comuns

**Erro: "comando 'dialog' não encontrado"**

```bash
sudo apt install dialog
```

**Interface corrompida**

```bash
reset  # Resetar terminal
clear  # Limpar tela
```

**Backup lento**

- Verificar velocidade do disco destino
- Usar destino em disco local para teste
- Verificar logs para arquivos grandes

**Permissões negadas**

```bash
# Verificar permissões
ls -la /caminho/destino
# Ajustar se necessário
chmod 755 /caminho/destino
```

### 10.2 Debug Mode

Para debug, adicione no início do script:

```bash
set -x  # Mostra comandos executados
```

---

## 11. Personalização e Extensões

### 11.1 Configurações Ajustáveis

```bash
# Profundidade da busca fuzzy
find "$HOME" -maxdepth 4 -type d

# Exclusões do rsync
--exclude='.DS_Store' --exclude='*.tmp'

# Destino padrão
"$HOME/backup"
```

### 11.2 Extensões Possíveis

- Compressão automática dos backups
- Notificações por email
- Integração com cloud storage
- Agendamento via cron
- Interface web

---

## 12. Segurança e Melhores Práticas

### 12.1 Considerações de Segurança

- Script valida todos os inputs
- Não executa comandos com privilégios elevados
- Logs não contêm informações sensíveis
- Caminhos são sanitizados

### 12.2 Melhores Práticas

- Teste sempre em ambiente controlado
- Mantenha backups em locais diferentes
- Verifique regularmente a integridade
- Use destinos com espaço suficiente
- Monitore logs de erro

---

## 13. Conclusão

O Script de Backup Interativo oferece uma solução robusta e amigável para backups em sistemas Linux. Com interface intuitiva e funcionalidades avançadas, atende desde usuários iniciantes até administradores experientes.

### 13.1 Vantagens

- Interface user-friendly
- Backup incremental eficiente
- Logging detalhado
- Tratamento robusto de erros
- Código modular e manutenível

### 13.2 Limitações

- Dependente de interface terminal
- Sem interface gráfica (GUI)
- Requer conhecimento básico de Linux

---

**Desenvolvido como projeto acadêmico para a UFPR**  
**Versão**: 0.0.1  
**Data**: 20/06/2025
