-- Додаємо UNIQUE constraint для fcm_token, який ми застосували вручну в SQL Editor
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'guardian_push_tokens_fcm_token_key'
  ) THEN
    ALTER TABLE public.guardian_push_tokens
      ADD CONSTRAINT guardian_push_tokens_fcm_token_key UNIQUE (fcm_token);
  END IF;
END $$;
