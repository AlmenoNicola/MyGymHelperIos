-- Bucket pubblico con le foto degli esercizi (Free Exercise DB, pubblico dominio), convertite in WebP (max 640 px).
-- Struttura: exercise-images/exercises/<id del dataset>/0.webp e 1.webp (gli URL completi sono in exercises_seed.json).
-- Il bucket è stato creato dalla dashboard il 28 ottobre 2026: questa migration serve a ricrearlo su un nuovo progetto.
insert into storage.buckets (id, name, public)
values ('exercise-images', 'exercise-images', true)
on conflict (id) do nothing;
