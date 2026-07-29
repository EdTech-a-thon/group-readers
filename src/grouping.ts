import type { Book } from "./lib";

export type GroupingStrategy = "overall" | "first" | "last";
export type GroupingSettings = { minimumSize: number; maximumSize: number; strategy: GroupingStrategy; bookLimits: Record<string, number> };
export type GroupingStudent = { id: string; firstName: string; lastInitial: string; choices: string[] };
export type GroupMember = GroupingStudent & { rank: number };
export type BookGroup = { bookId: string; groupNumber: number; members: GroupMember[] };
export type GroupingResult = { groups: BookGroup[]; unplaced: GroupingStudent[]; rankCounts: number[]; placed: number; score: number };

type Assignment = { bookIndex: number; rank: number } | undefined;
// "last" counts the placements at the bottom of a student's ranking — a fourth
// choice on a list where students rank four books.
type Candidate = { assignments: Assignment[]; placed: number; first: number; last: number; score: number; groupCounts: number[] };
type Edge = { to: number; reverse: number; capacity: number; cost: number; student?: number; book?: number; rank?: number; mandatory?: boolean };

// A first choice is worth more than a second, and each further step down the
// ranking gives up more than the step before it. However many books a list asks
// students to rank, the points come out as 10, 6, 3, 1 for a ranking of four.
function rankScore(rank: number, rankedBooks: number) {
  const stepsToBottom = rankedBooks - rank + 1;
  return (stepsToBottom * (stepsToBottom + 1)) / 2;
}

function isBetter(left: Candidate, right: Candidate | undefined, strategy: GroupingStrategy) {
  if (!right) return true;
  const comparisons = strategy === "first"
    ? [left.placed - right.placed, left.first - right.first, left.score - right.score, right.last - left.last]
    : strategy === "last"
      ? [left.placed - right.placed, right.last - left.last, left.score - right.score, left.first - right.first]
      : [left.placed - right.placed, left.score - right.score, left.first - right.first, right.last - left.last];
  return (comparisons.find((value) => value !== 0) || 0) > 0;
}

function addEdge(graph: Edge[][], from: number, edge: Omit<Edge, "reverse">) {
  const forward = { ...edge, reverse: graph[edge.to].length };
  const backward: Edge = { to: from, reverse: graph[from].length, capacity: 0, cost: -edge.cost };
  graph[from].push(forward);
  graph[edge.to].push(backward);
}

function assignForConfiguration(students: GroupingStudent[], books: Book[], groupCounts: number[], settings: GroupingSettings, rankedBooks: number): Candidate | undefined {
  const source = 0;
  const studentStart = 1;
  const slots: { bookIndex: number; mandatory: boolean; node: number }[] = [];
  groupCounts.forEach((groups, bookIndex) => {
    const minimum = groups * settings.minimumSize;
    const maximum = groups * settings.maximumSize;
    for (let index = 0; index < maximum; index++) slots.push({ bookIndex, mandatory: index < minimum, node: studentStart + students.length + slots.length });
  });
  const sink = studentStart + students.length + slots.length;
  const graph: Edge[][] = Array.from({ length: sink + 1 }, () => []);
  const bookIndexes = new Map(books.map((book, index) => [book.id, index]));
  // Each strategy bends the plain ranking points: chasing first choices makes a
  // first choice worth more than any pile of lower ones, and avoiding last
  // choices makes every other rank clearly preferable to the bottom one.
  const best = rankScore(1, rankedBooks);
  const strategyScore = (rank: number) => settings.strategy === "first" ? (rank === 1 ? best * 10 : rankScore(rank, rankedBooks)) : settings.strategy === "last" ? (rank === rankedBooks ? 0 : best * 2 + rankScore(rank, rankedBooks)) : rankScore(rank, rankedBooks);

  students.forEach((student, studentIndex) => {
    addEdge(graph, source, { to: studentStart + studentIndex, capacity: 1, cost: 0 });
    student.choices.forEach((bookId, rankIndex) => {
      const bookIndex = bookIndexes.get(bookId);
      if (bookIndex === undefined || groupCounts[bookIndex] === 0) return;
      slots.forEach((slot) => {
        if (slot.bookIndex !== bookIndex) return;
        addEdge(graph, studentStart + studentIndex, {
          to: slot.node,
          capacity: 1,
          cost: 1000 + strategyScore(rankIndex + 1) + (slot.mandatory ? 100000 : 0),
          student: studentIndex,
          book: bookIndex,
          rank: rankIndex + 1,
          mandatory: slot.mandatory,
        });
      });
    });
  });
  slots.forEach((slot) => addEdge(graph, slot.node, { to: sink, capacity: 1, cost: 0 }));

  while (true) {
    const distance = Array(graph.length).fill(-Infinity);
    const previousNode = Array(graph.length).fill(-1);
    const previousEdge = Array(graph.length).fill(-1);
    const queued = Array(graph.length).fill(false);
    const queue = [source];
    distance[source] = 0;
    queued[source] = true;
    for (let cursor = 0; cursor < queue.length; cursor++) {
      const node = queue[cursor];
      queued[node] = false;
      graph[node].forEach((edge, edgeIndex) => {
        if (edge.capacity > 0 && distance[node] + edge.cost > distance[edge.to]) {
          distance[edge.to] = distance[node] + edge.cost;
          previousNode[edge.to] = node;
          previousEdge[edge.to] = edgeIndex;
          if (!queued[edge.to]) { queue.push(edge.to); queued[edge.to] = true; }
        }
      });
    }
    if (previousNode[sink] < 0) break;
    for (let node = sink; node !== source; node = previousNode[node]) {
      const edge = graph[previousNode[node]][previousEdge[node]];
      edge.capacity -= 1;
      graph[node][edge.reverse].capacity += 1;
    }
  }

  const assignments: Assignment[] = Array(students.length).fill(undefined);
  const mandatoryFilled = books.map(() => 0);
  students.forEach((_, studentIndex) => {
    graph[studentStart + studentIndex].forEach((edge) => {
      if (edge.student === studentIndex && edge.capacity === 0 && edge.book !== undefined && edge.rank !== undefined) {
        assignments[studentIndex] = { bookIndex: edge.book, rank: edge.rank };
        if (edge.mandatory) mandatoryFilled[edge.book] += 1;
      }
    });
  });
  if (groupCounts.some((groups, index) => mandatoryFilled[index] !== groups * settings.minimumSize)) return undefined;
  const ranks = assignments.filter(Boolean).map((assignment) => assignment!.rank);
  return {
    assignments,
    placed: ranks.length,
    first: ranks.filter((rank) => rank === 1).length,
    last: ranks.filter((rank) => rank === rankedBooks).length,
    score: ranks.reduce((total, rank) => total + rankScore(rank, rankedBooks), 0),
    groupCounts,
  };
}

function groupSizes(count: number, groups: number) {
  const sizes = Array(groups).fill(Math.floor(count / groups));
  for (let index = 0; index < count % groups; index++) sizes[index] += 1;
  return sizes;
}

export function createGroups(books: Book[], students: GroupingStudent[], settings: GroupingSettings, rankedBooks: number): GroupingResult {
  const orderedStudents = [...students].sort((left, right) => `${left.firstName}|${left.lastInitial}|${left.id}`.localeCompare(`${right.firstName}|${right.lastInitial}|${right.id}`));
  const interested = books.map((book) => orderedStudents.filter((student) => student.choices.includes(book.id)).length);
  const maximumGroups = books.map((book, index) => Math.min(settings.bookLimits[book.id] || 0, Math.floor(interested[index] / settings.minimumSize), Math.floor(orderedStudents.length / settings.minimumSize)));
  let winner: Candidate | undefined;

  function visit(bookIndex: number, counts: number[], minimumStudents: number) {
    if (minimumStudents > orderedStudents.length) return;
    if (bookIndex === books.length) {
      const candidate = assignForConfiguration(orderedStudents, books, counts, settings, rankedBooks);
      if (candidate && isBetter(candidate, winner, settings.strategy)) winner = candidate;
      return;
    }
    for (let groups = 0; groups <= maximumGroups[bookIndex]; groups++) visit(bookIndex + 1, [...counts, groups], minimumStudents + groups * settings.minimumSize);
  }
  visit(0, [], 0);
  if (!winner) throw new Error("No grouping draft could be created.");

  const membersByBook = books.map(() => [] as GroupMember[]);
  const unplaced: GroupingStudent[] = [];
  const rankCounts = Array(rankedBooks).fill(0) as number[];
  winner.assignments.forEach((assignment, index) => {
    if (!assignment) return unplaced.push(orderedStudents[index]);
    membersByBook[assignment.bookIndex].push({ ...orderedStudents[index], rank: assignment.rank });
    rankCounts[assignment.rank - 1] += 1;
  });
  const groups: BookGroup[] = [];
  books.forEach((book, bookIndex) => {
    let offset = 0;
    groupSizes(membersByBook[bookIndex].length, winner!.groupCounts[bookIndex]).forEach((size, groupIndex) => {
      groups.push({ bookId: book.id, groupNumber: groupIndex + 1, members: membersByBook[bookIndex].slice(offset, offset + size) });
      offset += size;
    });
  });
  return { groups, unplaced, rankCounts, placed: winner.placed, score: winner.score };
}
