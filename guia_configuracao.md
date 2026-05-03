# Guia de Configuração — TradeGest Pro SaaS

## 1. Criar projeto no Supabase

1. Acesse [supabase.com](https://supabase.com) e crie uma conta
2. Clique em **"New Project"**
3. Escolha nome, senha do banco e região (preferencialmente São Paulo)
4. Aguarde a criação (≈2 min)

## 2. Executar o SQL

1. No painel do Supabase, vá em **SQL Editor** (menu lateral)
2. Clique em **"New Query"**
3. Cole todo o conteúdo do arquivo `supabase_schema.sql`
4. Clique em **"Run"**
5. Verifique se não houve erros (todas as tabelas, políticas e triggers serão criados)

## 3. Obter as credenciais

1. Vá em **Settings → API**
2. Copie:
   - **Project URL** (ex: `https://xyzcompany.supabase.co`)
   - **anon public key** (começa com `eyJ...`)
3. Abra o arquivo `index.html` e substitua:

```javascript
const SUPABASE_URL = 'SEU_SUPABASE_URL';        // ← cole o Project URL
const SUPABASE_KEY = 'SEU_SUPABASE_ANON_KEY';   // ← cole a anon key
```

## 4. Criar o primeiro Superadmin

Como o superadmin é o dono do sistema, ele precisa ser criado manualmente:

1. No Supabase, vá em **Authentication → Users**
2. Clique em **"Add User"** → **"Create New User"**
3. Preencha email e senha (ex: `admin@tradegest.com` / `senha123`)
4. Copie o **User UID** gerado
5. Vá no **SQL Editor** e execute:

UPDATE public.usuarios 
SET role = 'superadmin', nome = 'Super Admin'
WHERE id = 'COLE_O_UID_AQUI';
```

## 5. Testar o fluxo completo

### Login
1. Abra `index.html` no navegador
2. Faça login com o email/senha do superadmin
3. Você será redirecionado ao **Painel do Superadmin**

### Criar Planos
1. Vá na aba **Planos**
2. Crie planos (Básico, Pro, Enterprise) — já vêm 3 planos seed, mas pode editar

### Criar Admin
1. Vá na aba **Admins → + Novo Admin**
2. Preencha nome, email, senha e plano
3. Faça logout e login com a conta admin criada

### Admin: Criar Usuário
1. Logado como admin, vá em **Usuários → + Novo Usuário**
2. Crie um usuário final

### Usuário: Fluxo completo
1. Faça logout e login com o usuário criado
2. Configure uma sessão (capital, entrada, operações, vitórias, payout, stop loss)
3. Clique em **Iniciar Sessão**
4. Marque Win/Loss nas operações
5. Veja o **Dashboard** atualizar em tempo real
6. Consulte o **Histórico** e **Perfil**
7. Recarregue a página — a sessão ativa será restaurada automaticamente

## 6. Configurações importantes do Supabase

### Desabilitar cadastro público
Para impedir que qualquer pessoa crie conta:

1. Vá em **Authentication → Providers → Email**
2. Desmarque **"Enable Sign Up"** (apenas admins/superadmins criam contas)

### Habilitar recuperação de senha
1. Em **Authentication → Email Templates**
2. Configure o template de "Reset Password"
3. Em **URL Configuration**, defina o **Site URL** (onde o index.html está hospedado)

## Estrutura de arquivos

```
levy-planilha/
├── index.html           ← Aplicação completa (SPA)
├── supabase_schema.sql  ← SQL para o Supabase
└── guia_configuracao.md ← Este guia
```
