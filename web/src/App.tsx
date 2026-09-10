import { useMemo, useState } from "react";
import { Menu } from "lucide-react";
import { Sidebar } from "@/components/Sidebar";
import { DashboardHeader } from "@/components/DashboardHeader";
import { ActionCards } from "@/components/ActionCards";
import { ActionDialog } from "@/components/ActionDialog";
import { FileTable } from "@/components/FileTable";
import { Editor } from "@/components/Editor";
import { SignIn } from "@/components/SignIn";
import type { Tab } from "@/lib/data";
import type { Page } from "@/lib/types";
import { usePages } from "@/context/PagesContext";

export default function App() {
  const { user, pages, loading, error, retry, activePageId, openPage, createPage } = usePages();
  const [tab, setTab] = useState<Tab>("all");
  const [query, setQuery] = useState("");
  const [cardKind, setCardKind] = useState<string | null>(null);
  const [mobileNav, setMobileNav] = useState(false);

  const visiblePages = useMemo(() => {
    const q = query.trim().toLowerCase();
    const filtered = tab === "all" || tab === "recents" ? pages : pages;
    return filtered.filter(
      (p) => q === "" || p.name.toLowerCase().includes(q),
    );
  }, [tab, query, pages]);

  const activePage = pages.find((p) => p.id === activePageId) ?? null;

  if (!user) {
    return <SignIn />;
  }

  if (activePage) {
    return (
      <div className="flex h-screen bg-background">
        <Editor page={activePage} onBack={() => openPage("")} />
      </div>
    );
  }

  function openCard(kind: string) {
    if (kind === "blank") {
      createPage("Untitled file")
        .then((page) => openPage(page.id))
        .catch(() => {});
      return;
    }
    setCardKind(kind);
  }

  return (
    <div className="flex h-screen overflow-hidden bg-background">
      <div className={`${mobileNav ? "fixed inset-y-0 left-0 z-50 block" : "hidden"} lg:block`}>
        <Sidebar onNewFile={() => openCard("blank")} onOpenCard={openCard} />
      </div>
      {mobileNav && (
        <div className="fixed inset-0 z-40 bg-black/50 lg:hidden" onClick={() => setMobileNav(false)} />
      )}

      <main className="flex min-w-0 flex-1 flex-col overflow-y-auto px-6 pt-10 md:px-10 xl:px-[72px]">
        <div className="flex items-center justify-between xl:hidden">
          <button
            onClick={() => setMobileNav(true)}
            className="flex h-8 w-8 cursor-pointer items-center justify-center rounded-[5px] border border-border bg-surface text-secondary"
          >
            <Menu size={16} />
          </button>
        </div>

        {loading ? (
          <div className="mt-24 flex flex-col items-center gap-3 text-secondary">
            <div className="size-6 animate-spin rounded-full border-2 border-border border-t-primary" />
            <p className="text-[13px]">Loading your workspace…</p>
          </div>
        ) : error ? (
          <div className="mt-24 flex flex-col items-center gap-3 text-secondary">
            <p className="text-[13.5px]">{error}</p>
            <button
              onClick={retry}
              className="cursor-pointer rounded-[5px] border border-border bg-surface px-3 py-1.5 text-[12.5px] hover:bg-active"
            >
              Try again
            </button>
          </div>
        ) : (
          <>
            <DashboardHeader tab={tab} onTabChange={setTab} query={query} onQueryChange={setQuery} />
            <ActionCards onOpenCard={openCard} />
            <FileTable pages={visiblePages} onOpenFile={(p) => openPage(p.id)} />
          </>
        )}
      </main>

      <ActionDialog kind={cardKind} onClose={() => setCardKind(null)} />
    </div>
  );
}