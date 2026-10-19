insert into books (author_id, title, published_on, copies)
values ($1, $2, $3, $4)
returning id, author_id, title, published_on, copies
