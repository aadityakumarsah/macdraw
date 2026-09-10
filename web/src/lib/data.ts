export type Tab = "all" | "recents" | "created" | "folders" | "unsorted";

export const TABS: { id: Tab; label: string }[] = [
  { id: "all", label: "All" },
  { id: "recents", label: "Recents" },
  { id: "created", label: "Created by Me" },
  { id: "folders", label: "Folders" },
  { id: "unsorted", label: "Unsorted" },
];

export type FileItem = {
  id: string;
  name: string;
  location: string;
  created: string;
  edited: string;
  comments: number;
  author: string;
  tabs: Tab[];
};

export const FILES: FileItem[] = [
  {
    id: "r1",
    name: "react roadmap",
    location: "—",
    created: "15 min ago",
    edited: "15 min ago",
    comments: 0,
    author: "AS",
    tabs: ["all", "recents", "created", "unsorted"],
  },
  {
    id: "r2",
    name: "canvas ideas",
    location: "—",
    created: "2 hrs ago",
    edited: "2 hrs ago",
    comments: 0,
    author: "AS",
    tabs: ["recents", "created"],
  },
  {
    id: "r3",
    name: "budget flowchart",
    location: "—",
    created: "yesterday",
    edited: "yesterday",
    comments: 3,
    author: "RB",
    tabs: ["recents"],
  },
  {
    id: "r4",
    name: "onboarding sketch",
    location: "—",
    created: "3 days ago",
    edited: "3 days ago",
    comments: 1,
    author: "JT",
    tabs: ["created"],
  },
];