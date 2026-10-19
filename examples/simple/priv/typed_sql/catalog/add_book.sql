with author as (
  insert into authors (name) values ($1)
  on conflict (name) do update set name = excluded.name
  returning id
)
insert into books (author_id, title, published_on)
select id, $2, $3 from author
returning id, title
