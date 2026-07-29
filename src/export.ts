import type { GroupingResult } from "./grouping";
import type { Book } from "./lib";

// Excel and Google Sheets both open a comma-separated file directly, so a draft
// can leave here and come back as a teacher's own edited copy without asking
// them to install anything.

// A field only needs quoting when it holds a comma, a quote, or a line break,
// and a quote inside a quoted field is written twice.
function csvField(value: string | number) {
  const text = String(value);
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

function csvFile(rows: (string | number)[][]) {
  // The byte order mark is what tells Excel the file is UTF-8, without which a
  // title carrying an accent or a curly quote arrives mangled.
  return `﻿${rows.map((row) => row.map(csvField).join(",")).join("\r\n")}\r\n`;
}

// One row per student, with the book and group in columns a teacher can retype.
// Students the draft could not place come last, still named, so nobody drops out
// of the list on the way to the spreadsheet.
export function groupsToCsv(result: GroupingResult, books: Book[]) {
  const titles = new Map(books.map((book) => [book.id, book.title]));
  const rows: (string | number)[][] = [["Book", "Group", "Student", "Choice (1 = first)", "Notes"]];

  for (const group of result.groups) {
    for (const member of group.members) {
      rows.push([
        titles.get(group.bookId) || "",
        group.groupNumber,
        `${member.firstName} ${member.lastInitial}.`,
        member.rank,
        "",
      ]);
    }
  }
  for (const student of result.unplaced) {
    rows.push(["", "", `${student.firstName} ${student.lastInitial}.`, "", "Needs placement"]);
  }
  return csvFile(rows);
}

// Anything a file system might object to becomes a dash, so a book list named
// "Period 3 / 4" still downloads.
function fileName(listName: string) {
  const cleaned = listName.replace(/[\\/:*?"<>|]+/g, "-").trim() || "Book list";
  return `${cleaned} groups.csv`;
}

export function downloadGroups(result: GroupingResult, books: Book[], listName: string) {
  const url = URL.createObjectURL(new Blob([groupsToCsv(result, books)], { type: "text/csv;charset=utf-8" }));
  const link = document.createElement("a");
  link.href = url;
  link.download = fileName(listName);
  link.click();
  URL.revokeObjectURL(url);
}
