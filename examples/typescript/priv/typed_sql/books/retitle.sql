update books
set title = $2
where id = $1
returning id, author_id, title, published_on, copies
