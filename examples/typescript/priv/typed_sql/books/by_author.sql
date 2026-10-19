select id, author_id, title, published_on, copies
from books
where author_id = $1
order by published_on nulls last, title
