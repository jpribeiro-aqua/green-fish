/* Configuração do app RAS Multitanques.
   Deixe em branco para o modo demonstração (usuários e senhas só neste aparelho).
   Para login de verdade, cole aqui o endereço e a chave pública (anon) do seu projeto Supabase:
   Supabase > Project Settings > API > Project URL e anon public key. */
window.RAS_CONFIG = {
  supabaseUrl: "",
  supabaseAnonKey: "",
  /* Versão básica no celular: false = só login de usuário; a administração aparece como "versão avançada" bloqueada.
     Para liberar a administração também no celular, troque para true. */
  adminNoCelular: false
};
