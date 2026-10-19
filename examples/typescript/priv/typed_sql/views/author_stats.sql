select
  a.id as author_id,
  (select count(*) from shelf.books b where b.author_id = a.id) as book_count,
  (select count(*) from shelf.loans l join shelf.books b on b.id = l.book_id where b.author_id = a.id) as loan_count,
  (select avg(r.rating) from shelf.reviews r join shelf.books b on b.id = r.book_id where b.author_id = a.id) as average_rating
from shelf.authors a
