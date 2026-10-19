select b.id, b.title, a.name as author_name, avg(r.rating) as average_rating, count(r.id) as review_count
from shelf.books b
join shelf.authors a on a.id = b.author_id
left join shelf.reviews r on r.book_id = b.id
group by b.id, b.title, a.name
order by average_rating desc nulls last, b.title
limit $1
