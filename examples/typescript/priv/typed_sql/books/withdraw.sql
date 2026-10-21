delete from shelf.books
where id = $1
returning id, author_id, title, published_on, copies
