-- ══════════════════════════════════════════════════
--  TRADE SAAS — SUPABASE SCHEMA COMPLETO (FINAL RECOVERY)
--  ESTE SCRIPT RESETA O BANCO E RESOLVE ERROS DE SCHEMA
-- ══════════════════════════════════════════════════

-- ─── 0) LIMPEZA TOTAL (RESET NUCLEAR) ───
-- CUIDADO: Isso apaga todas as tabelas no schema public.
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;

-- ─── 1) PERMISSÕES DE API (ESSENCIAL PARA POSTGREST) ───
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;

-- Habilitar pgcrypto para senhas
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ─── 2) TABELAS ───

CREATE TABLE public.planos (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  nome        TEXT NOT NULL,
  max_usuarios INT NOT NULL DEFAULT 10,
  preco       DECIMAL(10,2) NOT NULL DEFAULT 0,
  ativo       BOOLEAN DEFAULT true,
  criado_em   TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.usuarios (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email           TEXT NOT NULL,
  nome            TEXT NOT NULL DEFAULT '',
  role            TEXT NOT NULL CHECK (role IN ('superadmin', 'admin', 'user')) DEFAULT 'user',
  plano_id        UUID REFERENCES public.planos(id) ON DELETE SET NULL,
  admin_id        UUID REFERENCES public.usuarios(id) ON DELETE SET NULL,
  ativo           BOOLEAN DEFAULT true,
  criado_em       TIMESTAMPTZ DEFAULT now(),
  ultimo_acesso   TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.clientes_admin (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  usuario_id      UUID NOT NULL REFERENCES public.usuarios(id) ON DELETE CASCADE,
  plano_id        UUID REFERENCES public.planos(id) ON DELETE SET NULL,
  max_usuarios    INT NOT NULL DEFAULT 10,
  usuarios_ativos INT NOT NULL DEFAULT 0,
  criado_em       TIMESTAMPTZ DEFAULT now(),
  UNIQUE(usuario_id)
);

CREATE TABLE public.membros (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  admin_id    UUID NOT NULL REFERENCES public.usuarios(id) ON DELETE CASCADE,
  usuario_id  UUID NOT NULL REFERENCES public.usuarios(id) ON DELETE CASCADE,
  ativo       BOOLEAN DEFAULT true,
  criado_em   TIMESTAMPTZ DEFAULT now(),
  UNIQUE(admin_id, usuario_id)
);

CREATE TABLE public.sessoes (
  id                UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  usuario_id        UUID NOT NULL REFERENCES public.usuarios(id) ON DELETE CASCADE,
  capital           DECIMAL(12,2) NOT NULL,
  valor_entrada     DECIMAL(12,2) NOT NULL,
  total_ops         INT NOT NULL DEFAULT 0,
  wins_esperados    INT NOT NULL DEFAULT 0,
  payout            DECIMAL(6,4) NOT NULL DEFAULT 1.85,
  stop_loss_pct     DECIMAL(5,2) NOT NULL DEFAULT 25,
  capital_final     DECIMAL(12,2),
  resultado_liquido DECIMAL(12,2),
  status            TEXT NOT NULL CHECK (status IN ('ativa', 'concluida')) DEFAULT 'ativa',
  criado_em         TIMESTAMPTZ DEFAULT now(),
  concluida_em      TIMESTAMPTZ
);

CREATE TABLE public.operacoes (
  id                UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  sessao_id         UUID NOT NULL REFERENCES public.sessoes(id) ON DELETE CASCADE,
  usuario_id        UUID NOT NULL REFERENCES public.usuarios(id) ON DELETE CASCADE,
  nome              TEXT NOT NULL DEFAULT '',
  valor_entrada     DECIMAL(12,2) NOT NULL,
  resultado         TEXT NOT NULL CHECK (resultado IN ('win', 'loss', 'pendente')) DEFAULT 'pendente',
  lucro             DECIMAL(12,2) DEFAULT 0,
  capital_apos      DECIMAL(12,2),
  horario_registro  TIMESTAMPTZ,
  criado_em         TIMESTAMPTZ DEFAULT now(),
  ordem             INT NOT NULL DEFAULT 0
);

-- ─── 3) ÍNDICES ───
CREATE INDEX idx_usuarios_role ON public.usuarios(role);
CREATE INDEX idx_sessoes_uid ON public.sessoes(usuario_id);
CREATE INDEX idx_operacoes_sid ON public.operacoes(sessao_id);

-- ─── 4) SEGURANÇA (RLS) COM JWT (SEM CONFLITOS) ───

-- Funções baseadas no JWT (Não consultam tabelas = Sem recursão)
CREATE OR REPLACE FUNCTION public.get_my_role() RETURNS TEXT AS $$
  SELECT (auth.jwt() -> 'user_metadata' ->> 'role')::text;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION public.is_superadmin() RETURNS BOOLEAN AS $$
  SELECT public.get_my_role() = 'superadmin';
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION public.is_admin() RETURNS BOOLEAN AS $$
  SELECT public.get_my_role() = 'admin';
$$ LANGUAGE sql STABLE;

-- Aplicar RLS
ALTER TABLE planos         ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuarios       ENABLE ROW LEVEL SECURITY;
ALTER TABLE clientes_admin ENABLE ROW LEVEL SECURITY;
ALTER TABLE membros        ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessoes        ENABLE ROW LEVEL SECURITY;
ALTER TABLE operacoes      ENABLE ROW LEVEL SECURITY;

-- Políticas Estáveis Baseadas puramente em tabelas e metadados JWT (RECURSION-SAFE)
CREATE POLICY "pl_sel" ON planos FOR SELECT TO authenticated USING (ativo = true OR public.is_superadmin());
CREATE POLICY "pl_all" ON planos FOR ALL TO authenticated    USING (public.is_superadmin());

-- Usuarios: Atualização do último acesso agora é livre para o próprio usuário
CREATE POLICY "u_self_select"  ON usuarios FOR SELECT TO authenticated USING (id = auth.uid());
CREATE POLICY "u_self_update"  ON usuarios FOR UPDATE TO authenticated USING (id = auth.uid());
CREATE POLICY "u_all"          ON usuarios FOR ALL    TO authenticated USING (public.is_superadmin());
CREATE POLICY "u_admin_select" ON usuarios FOR SELECT TO authenticated USING (
  public.is_admin() AND EXISTS (SELECT 1 FROM public.membros m WHERE m.admin_id = auth.uid() AND m.usuario_id = usuarios.id)
);
CREATE POLICY "u_admin_update" ON usuarios FOR UPDATE TO authenticated USING (
  public.is_admin() AND EXISTS (SELECT 1 FROM public.membros m WHERE m.admin_id = auth.uid() AND m.usuario_id = usuarios.id)
);

CREATE POLICY "ca_all" ON clientes_admin FOR ALL TO authenticated USING (usuario_id = auth.uid() OR public.is_superadmin());

CREATE POLICY "m_all"  ON membros FOR ALL TO authenticated USING (admin_id = auth.uid() OR public.is_superadmin());
CREATE POLICY "m_sel"  ON membros FOR SELECT TO authenticated USING (usuario_id = auth.uid());

CREATE POLICY "s_self" ON sessoes FOR ALL TO authenticated USING (usuario_id = auth.uid());
CREATE POLICY "s_mgr"  ON sessoes FOR SELECT TO authenticated USING (
  public.is_superadmin() OR (public.is_admin() AND EXISTS (SELECT 1 FROM public.membros m WHERE m.admin_id = auth.uid() AND m.usuario_id = sessoes.usuario_id))
);

CREATE POLICY "o_self" ON operacoes FOR ALL TO authenticated USING (usuario_id = auth.uid());
CREATE POLICY "o_mgr"  ON operacoes FOR SELECT TO authenticated USING (
  public.is_superadmin() OR (public.is_admin() AND EXISTS (SELECT 1 FROM public.membros m WHERE m.admin_id = auth.uid() AND m.usuario_id = operacoes.usuario_id))
);


-- Atualizar contagem de membros
CREATE OR REPLACE FUNCTION public.update_usuarios_ativos() RETURNS TRIGGER AS $$
DECLARE target_uid UUID;
BEGIN
  target_uid := CASE WHEN TG_OP = 'DELETE' THEN OLD.admin_id ELSE NEW.admin_id END;
  UPDATE public.clientes_admin SET usuarios_ativos = (SELECT COUNT(*) FROM public.membros WHERE admin_id = target_uid AND ativo = true) WHERE usuario_id = target_uid;
  RETURN NULL;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_membro_change AFTER INSERT OR UPDATE OR DELETE ON membros FOR EACH ROW EXECUTE FUNCTION public.update_usuarios_ativos();


-- ─── 6) GATILHO: AUTO-INSERIR USUÁRIOS CRIADOS PELO SUPABASE ───
CREATE OR REPLACE FUNCTION public.handle_new_user() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.usuarios (id, email, nome, role, ativo)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'nome', split_part(NEW.email, '@', 1)),
    COALESCE(NEW.raw_user_meta_data->>'role', 'user'),
    true
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ─── 7) SEED — Planos padrão ───
INSERT INTO public.planos (nome, max_usuarios, preco) VALUES
  ('Básico', 10, 97.00), ('Profissional', 50, 197.00), ('Enterprise', 200, 497.00);

-- Finalizar
NOTIFY pgrst, 'reload schema';
