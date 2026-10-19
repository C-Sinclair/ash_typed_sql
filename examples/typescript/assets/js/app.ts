import "../css/app.css";
import {
  addBook,
  booksByAuthor,
  borrowBook,
  buildCSRFHeaders,
  listAuthors,
  listAuthorStats,
  listBooks,
  listLoans,
  listMembers,
  popularBooks,
  refreshAuthorStats,
  retitleBook,
  returnLoan,
  topRatedBooks,
  withdrawBook,
} from "./ash_rpc";
import type { AshRpcError } from "./ash_types";

type Child = Node | string | number | null | undefined;

function h(tag: string, attrs: Record<string, string> = {}, ...children: Child[]): HTMLElement {
  const element = document.createElement(tag);
  for (const [name, value] of Object.entries(attrs)) element.setAttribute(name, value);
  for (const child of children) {
    if (child === null || child === undefined) continue;
    element.append(child instanceof Node ? child : String(child));
  }
  return element;
}

function button(label: string, onClick: () => Promise<void>): HTMLElement {
  const element = h("button", { type: "button" }, label);
  element.addEventListener("click", () => void onClick());
  return element;
}

function table(headers: string[], rows: Child[][]): HTMLElement {
  return h(
    "table",
    {},
    h("thead", {}, h("tr", {}, ...headers.map((header) => h("th", {}, header)))),
    h("tbody", {}, ...rows.map((row) => h("tr", {}, ...row.map((cell) => h("td", {}, cell))))),
  );
}

function errorText(errors: AshRpcError[]): HTMLElement {
  return h("p", { class: "error" }, errors.map((error) => error.message).join("; "));
}

function section(id: string, title: string, feature: string): { root: HTMLElement; body: HTMLElement } {
  const body = h("div", { class: "body" });
  const root = h("section", { id }, h("h2", {}, title), h("p", { class: "feature" }, feature), body);
  return { root, body };
}

const headers = buildCSRFHeaders();
const today = new Date().toISOString().slice(0, 10);

async function renderBooks(body: HTMLElement): Promise<void> {
  const result = await listBooks({
    fields: ["id", "title", "publishedOn", "copies", { author: ["name"] }],
    sort: "title",
    headers,
  });
  if (!result.success) return void body.replaceChildren(errorText(result.errors));

  const rows = result.data.map((book) => [
    book.title,
    book.author?.name,
    book.publishedOn,
    book.copies,
    h(
      "span",
      {},
      button("Retitle", async () => {
        const title = window.prompt("New title", book.title);
        if (!title) return;
        const update = await retitleBook({ identity: book.id, input: { title }, fields: ["title"], headers });
        if (!update.success) return void body.append(errorText(update.errors));
        await refreshAll();
      }),
      button("Withdraw", async () => {
        const destroy = await withdrawBook({ identity: book.id, headers });
        if (!destroy.success) return void body.append(errorText(destroy.errors));
        await refreshAll();
      }),
    ),
  ]);

  body.replaceChildren(table(["Title", "Author", "Published", "Copies", ""], rows), await addBookForm());
}

async function addBookForm(): Promise<HTMLElement> {
  const authors = await listAuthors({ fields: ["id", "name"], sort: "name", headers });
  const select = h("select", { name: "authorId" }) as HTMLSelectElement;
  if (authors.success) {
    for (const author of authors.data) select.append(h("option", { value: author.id }, author.name));
  }
  const title = h("input", { name: "title", placeholder: "Title", required: "" }) as HTMLInputElement;
  const publishedOn = h("input", { name: "publishedOn", type: "date", value: today }) as HTMLInputElement;
  const form = h("form", {}, select, title, publishedOn, h("button", { type: "submit" }, "Add book"));

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    void (async () => {
      const created = await addBook({
        input: { authorId: select.value, title: title.value, publishedOn: publishedOn.value, copies: 1 },
        fields: ["id", "title"],
        headers,
      });
      if (!created.success) return void form.append(errorText(created.errors));
      await refreshAll();
    })();
  });

  return form;
}

async function renderTopRated(body: HTMLElement): Promise<void> {
  const result = await topRatedBooks({
    input: { limit: 3 },
    fields: ["title", "authorName", "averageRating", "reviewCount"],
    headers,
  });
  if (!result.success) return void body.replaceChildren(errorText(result.errors));

  const rows = result.data.map((row) => [row.title, row.authorName, row.averageRating ?? "no reviews", row.reviewCount]);
  body.replaceChildren(table(["Title", "Author", "Average rating", "Reviews"], rows));
}

async function renderByAuthor(body: HTMLElement): Promise<void> {
  const authors = await listAuthors({ fields: ["id", "name"], sort: "name", headers });
  if (!authors.success) return void body.replaceChildren(errorText(authors.errors));

  const select = h("select", {}) as HTMLSelectElement;
  for (const author of authors.data) select.append(h("option", { value: author.id }, author.name));
  const results = h("div", {});

  const load = async () => {
    const books = await booksByAuthor({ input: { authorId: select.value }, fields: ["title", "publishedOn"], headers });
    if (!books.success) return void results.replaceChildren(errorText(books.errors));
    results.replaceChildren(table(["Title", "Published"], books.data.map((book) => [book.title, book.publishedOn])));
  };

  select.addEventListener("change", () => void load());
  body.replaceChildren(select, results);
  await load();
}

async function renderLoans(body: HTMLElement, overdueOnly: boolean): Promise<void> {
  const result = await listLoans({
    fields: ["id", "dueOn", "returnedOn", "overdueDays", { book: ["title"] }, { member: ["name"] }],
    filter: overdueOnly ? { overdueDays: { greaterThan: 0 }, returnedOn: { isNil: true } } : undefined,
    sort: "dueOn",
    headers,
  });
  if (!result.success) return void body.replaceChildren(errorText(result.errors));

  const toggle = button(overdueOnly ? "Show all loans" : "Show overdue only", () => renderLoans(body, !overdueOnly));
  const rows = result.data.map((loan) => [
    loan.book?.title,
    loan.member?.name,
    loan.dueOn,
    loan.returnedOn ?? "out",
    loan.overdueDays,
    loan.returnedOn
      ? null
      : button("Return", async () => {
          const returned = await returnLoan({ input: { id: loan.id }, fields: ["returnedOn"], headers });
          if (!returned.success) return void body.append(errorText(returned.errors));
          await refreshAll();
        }),
  ]);

  body.replaceChildren(toggle, table(["Book", "Member", "Due", "Returned", "Days overdue", ""], rows), await borrowForm());
}

async function borrowForm(): Promise<HTMLElement> {
  const [books, members] = await Promise.all([
    listBooks({ fields: ["id", "title"], sort: "title", headers }),
    listMembers({ fields: ["id", "name"], sort: "name", headers }),
  ]);
  const bookSelect = h("select", {}) as HTMLSelectElement;
  const memberSelect = h("select", {}) as HTMLSelectElement;
  if (books.success) for (const book of books.data) bookSelect.append(h("option", { value: book.id }, book.title));
  if (members.success) for (const member of members.data) memberSelect.append(h("option", { value: member.id }, member.name));
  const form = h("form", {}, bookSelect, memberSelect, h("button", { type: "submit" }, "Borrow for 14 days"));

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    void (async () => {
      const borrowed = await borrowBook({
        input: { bookId: bookSelect.value, memberId: memberSelect.value, days: 14 },
        fields: ["id", "dueOn"],
        headers,
      });
      if (!borrowed.success) return void form.append(errorText(borrowed.errors));
      await refreshAll();
    })();
  });

  return form;
}

async function renderAuthorStats(body: HTMLElement): Promise<void> {
  const result = await listAuthorStats({
    fields: ["bookCount", "loanCount", "averageRating", { author: ["name"] }],
    sort: "-loanCount",
    headers,
  });
  if (!result.success) return void body.replaceChildren(errorText(result.errors));

  const refresh = button("Refresh materialized view", async () => {
    const refreshed = await refreshAuthorStats({ headers });
    if (!refreshed.success) return void body.append(errorText(refreshed.errors));
    await renderAuthorStats(body);
  });
  const rows = result.data.map((row) => [row.author?.name, row.bookCount, row.loanCount, row.averageRating]);
  body.replaceChildren(refresh, table(["Author", "Books", "Loans", "Average rating"], rows));
}

async function renderPopular(body: HTMLElement, since: string): Promise<void> {
  const result = await popularBooks({
    input: { since },
    fields: ["title", "loanCount"],
    filter: { loanCount: { greaterThan: 0 } },
    sort: ["-loanCount", "title"],
    headers,
  });
  if (!result.success) return void body.replaceChildren(errorText(result.errors));

  const input = h("input", { type: "date", value: since }) as HTMLInputElement;
  input.addEventListener("change", () => void renderPopular(body, input.value));
  const rows = result.data.map((row) => [row.title, row.loanCount]);
  body.replaceChildren(h("label", {}, "Borrowed since ", input), table(["Title", "Loans"], rows));
}

const books = section("books", "Books", "View with a relationship (books.sql), plus as :create, :update and :destroy queries");
const topRated = section("top-rated", "Top rated", "Generic read query (top_rated.sql)");
const byAuthor = section("by-author", "Books by author", "as :read query (by_author.sql)");
const loans = section("loans", "Loans", "SQL function days_overdue in a calculation and filter, generic write queries borrow.sql and return_loan.sql");
const authorStats = section("author-stats", "Author stats", "Materialized view with :refresh (author_stats.sql)");
const popular = section("popular", "Popular books", "Parameterized view (popular_books.sql)");
const popularSince = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);

async function refreshAll(): Promise<void> {
  await Promise.all([
    renderBooks(books.body),
    renderTopRated(topRated.body),
    renderByAuthor(byAuthor.body),
    renderLoans(loans.body, false),
    renderAuthorStats(authorStats.body),
    renderPopular(popular.body, popularSince),
  ]);
}

const app = document.getElementById("app");
if (app) {
  app.append(
    h("h1", {}, "Bookshelf"),
    h("p", {}, "Every call below is an ash_typescript RPC function generated from an action that ash_typed_sql built from SQL."),
    books.root,
    topRated.root,
    byAuthor.root,
    loans.root,
    authorStats.root,
    popular.root,
  );
  void refreshAll();
}
