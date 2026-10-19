select b.id as book_id, count(r.id) as review_count, avg(r.rating) as average_rating
from books b
left join reviews r on r.book_id = b.id
group by b.id
