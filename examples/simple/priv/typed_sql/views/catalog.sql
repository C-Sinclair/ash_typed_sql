select b.id, b.title, b.published_on, b.author_id, a.name as author_name
from books b
join authors a on a.id = b.author_id
