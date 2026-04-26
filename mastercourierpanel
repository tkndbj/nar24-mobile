"use client";

import { useEffect, useState, useCallback } from "react";
import { useRouter } from "next/navigation";
import {
  Plus,
  Trash2,
  ChevronDown,
  ChevronLeft,
  Layers,
  X,
  Upload,
  AlertCircle,
  CheckCircle2,
  LayoutList,
} from "lucide-react";
import {
  doc,
  getDoc,
  setDoc,
  serverTimestamp,
} from "firebase/firestore";
import { db } from "../lib/firebase";
import { useAuth } from "@/contexts/AuthContext";
import ProtectedRoute from "@/components/ProtectedRoute";
import { DEFAULT_CATEGORY_DATA } from "../defaultCategoryData";

// ─── Types ───────────────────────────────────────────────────────────────────

interface Labels {
  tr: string;
  en: string;
  ru: string;
}

interface BuyerSubSubcategory {
  key: string;
  labels: Labels;
}

interface BuyerSubcategory {
  key: string;
  labels: Labels;
  subSubcategories: BuyerSubSubcategory[];
}

interface BuyerCategory {
  key: string;
  image: string;
  labels: Labels;
  subcategories: BuyerSubcategory[];
}

interface CategoryStructure {
  buyerCategories: BuyerCategory[];
  buyerToProductMapping: Record<string, Record<string, string>>;
}

interface CategoryMeta {
  version: string;
  updatedAt: unknown;
  updatedBy: string;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

const SUPPORTED_LANGS = [
  { code: "tr", flag: "🇹🇷", label: "Türkçe" },
  { code: "en", flag: "🇬🇧", label: "English" },
  { code: "ru", flag: "🇷🇺", label: "Русский" },
];

const ACCENT_COLORS = [
  "bg-blue-500", "bg-violet-500", "bg-pink-500", "bg-orange-500",
  "bg-emerald-500", "bg-cyan-500", "bg-amber-500", "bg-indigo-500",
  "bg-teal-500", "bg-lime-500", "bg-red-500", "bg-slate-500",
];

function getAccent(i: number) {
  return ACCENT_COLORS[i % ACCENT_COLORS.length];
}

function generateVersion(): string {
  return new Date().toISOString().slice(0, 16).replace("T", "-");
}

function emptyLabels(): Labels {
  return { tr: "", en: "", ru: "" };
}

// ─── Label Input Component ────────────────────────────────────────────────────

function LabelInputs({
  labels,
  onChange,
  placeholder,
}: {
  labels: Labels;
  onChange: (lang: keyof Labels, value: string) => void;
  placeholder?: string;
}) {
  return (
    <div className="flex flex-col gap-1.5">
      {SUPPORTED_LANGS.map(({ code, flag, label }) => (
        <div key={code} className="flex items-center gap-2">
          <span className="text-sm w-6 text-center">{flag}</span>
          <input
            type="text"
            value={labels[code as keyof Labels]}
            onChange={(e) => onChange(code as keyof Labels, e.target.value)}
            placeholder={`${label}${placeholder ? ` — ${placeholder}` : ""}`}
            className="flex-1 text-xs border border-gray-200 rounded-lg px-3 py-2 outline-none focus:border-blue-400 focus:ring-2 focus:ring-blue-100 transition-all"
          />
        </div>
      ))}
    </div>
  );
}

// ─── Add Category Modal ───────────────────────────────────────────────────────

function AddModal({
  title,
  onConfirm,
  onCancel,
}: {
  title: string;
  onConfirm: (key: string, labels: Labels) => void;
  onCancel: () => void;
}) {
  const [key, setKey] = useState("");
  const [labels, setLabels] = useState<Labels>(emptyLabels());

  function handleLabelChange(lang: keyof Labels, value: string) {
    setLabels((prev) => ({ ...prev, [lang]: value }));
  }

  function handleConfirm() {
    const k = key.trim() || labels.en.trim() || labels.tr.trim();
    if (!k) return;
    onConfirm(k, {
      tr: labels.tr.trim() || k,
      en: labels.en.trim() || k,
      ru: labels.ru.trim() || k,
    });
  }

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-md p-6">
        <h3 className="text-sm font-bold text-gray-900 mb-4">{title}</h3>

        <div className="mb-4">
          <label className="text-xs font-semibold text-gray-500 mb-1.5 block">
            Anahtar (key) — veritabanında saklanır
          </label>
          <input
            type="text"
            value={key}
            onChange={(e) => setKey(e.target.value)}
            placeholder="Örn: summer_collection"
            className="w-full text-xs border border-gray-200 rounded-lg px-3 py-2 outline-none focus:border-blue-400 focus:ring-2 focus:ring-blue-100"
          />
          <p className="text-[10px] text-gray-400 mt-1">
            Boş bırakılırsa İngilizce isim kullanılır
          </p>
        </div>

        <div className="mb-5">
          <label className="text-xs font-semibold text-gray-500 mb-1.5 block">
            Görünen İsimler
          </label>
          <LabelInputs labels={labels} onChange={handleLabelChange} />
        </div>

        <div className="flex gap-2 justify-end">
          <button
            onClick={onCancel}
            className="px-4 py-2 text-xs font-medium text-gray-600 bg-gray-100 rounded-lg hover:bg-gray-200 transition-colors"
          >
            İptal
          </button>
          <button
            onClick={handleConfirm}
            className="px-4 py-2 text-xs font-semibold text-white bg-blue-600 rounded-lg hover:bg-blue-700 transition-colors"
          >
            Ekle
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Main Component ───────────────────────────────────────────────────────────

export default function CategoriesPage() {
  const { user } = useAuth();
  const router = useRouter();

  const [structure, setStructure] = useState<CategoryStructure | null>(null);
  const [meta, setMeta] = useState<CategoryMeta | null>(null);
  const [selectedIndex, setSelectedIndex] = useState<number | null>(null);
  const [expandedSubs, setExpandedSubs] = useState<Set<number>>(new Set());
  const [hasChanges, setHasChanges] = useState(false);
  const [loading, setLoading] = useState(true);
  const [publishing, setPublishing] = useState(false);
  const [toast, setToast] = useState<{ msg: string; type: "success" | "warn" } | null>(null);

  // Modal state
  const [addModal, setAddModal] = useState<{
    type: "category" | "subcategory" | "subsubcategory";
    subIdx?: number;
  } | null>(null);

  
  // ── Toast ────────────────────────────────────────────────────────────────────

  const showToast = useCallback((msg: string, type: "success" | "warn" = "success") => {
    setToast({ msg, type });
    setTimeout(() => setToast(null), 3000);
  }, []);

  // ── Load ────────────────────────────────────────────────────────────────────

  useEffect(() => {
    async function load() {
      try {
        const [metaSnap, structSnap] = await Promise.all([
          getDoc(doc(db, "categories", "meta")),
          getDoc(doc(db, "categories", "structure")),
        ]);
        setStructure(structSnap.exists()
          ? (structSnap.data() as CategoryStructure)
          : (DEFAULT_CATEGORY_DATA as CategoryStructure));
        if (metaSnap.exists()) setMeta(metaSnap.data() as CategoryMeta);
      } catch {
        setStructure(DEFAULT_CATEGORY_DATA as CategoryStructure);
        showToast("Firestore'dan yüklenemedi, varsayılan veri kullanılıyor.", "warn");
      } finally {
        setLoading(false);
      }
    }
    load();
  }, [showToast]);


  // ── Publish ──────────────────────────────────────────────────────────────────

  async function handlePublish() {
    if (!structure) return;
    setPublishing(true);
    try {
      const version = generateVersion();
      await Promise.all([
        setDoc(doc(db, "categories", "structure"), structure),
        setDoc(doc(db, "categories", "meta"), {
          version,
          updatedAt: serverTimestamp(),
          updatedBy: user?.email ?? "admin",
        }),
      ]);
      setMeta({ version, updatedAt: new Date(), updatedBy: user?.email ?? "admin" });
      setHasChanges(false);
      showToast("Firestore'a başarıyla yayınlandı!");
    } catch {
      showToast("Yayınlama başarısız. Tekrar deneyin.", "warn");
    } finally {
      setPublishing(false);
    }
  }

  // ── Mutations ────────────────────────────────────────────────────────────────

  function update(updater: (draft: CategoryStructure) => void) {
    setStructure((prev) => {
      if (!prev) return prev;
      const next = JSON.parse(JSON.stringify(prev)) as CategoryStructure;
      updater(next);
      return next;
    });
    setHasChanges(true);
  }

  // Category label edit
  function updateCategoryLabel(i: number, lang: keyof Labels, value: string) {
    update((d) => {
      // ✅ Guard: initialize labels if missing
      if (!d.buyerCategories[i].labels) {
        d.buyerCategories[i].labels = { tr: "", en: "", ru: "" };
      }
      d.buyerCategories[i].labels[lang] = value;
    });
  }

  function deleteBuyerCategory(i: number) {
    const key = structure!.buyerCategories[i].key;
    if (!confirm(`"${key}" silinsin mi?`)) return;
    update((d) => { d.buyerCategories.splice(i, 1); });
    if (selectedIndex === i) setSelectedIndex(null);
    else if (selectedIndex !== null && selectedIndex > i) setSelectedIndex(selectedIndex - 1);
    showToast(`"${key}" silindi`, "warn");
  }

  function addBuyerCategory(key: string, labels: Labels) {
    update((d) => {
      d.buyerCategories.push({ key, image: "", labels, subcategories: [] });
    });
    setSelectedIndex((structure?.buyerCategories.length ?? 0));
    showToast(`"${labels.en}" eklendi`);
    setAddModal(null);
  }

  // Subcategory label edit
  function updateSubcategoryLabel(si: number, lang: keyof Labels, value: string) {
    if (selectedIndex === null) return;
    update((d) => {
      // ✅ Guard: initialize labels if missing
      if (!d.buyerCategories[selectedIndex].subcategories[si].labels) {
        d.buyerCategories[selectedIndex].subcategories[si].labels = { tr: "", en: "", ru: "" };
      }
      d.buyerCategories[selectedIndex].subcategories[si].labels[lang] = value;
    });
  }

  function addSubcategory(key: string, labels: Labels) {
    if (selectedIndex === null) return;
    update((d) => {
      d.buyerCategories[selectedIndex].subcategories.push({
        key, labels, subSubcategories: [],
      });
    });
    showToast(`"${labels.en}" eklendi`);
    setAddModal(null);
  }

  function deleteSubcategory(si: number) {
    if (selectedIndex === null) return;
    const key = structure!.buyerCategories[selectedIndex].subcategories[si].key;
    if (!confirm(`"${key}" silinsin mi?`)) return;
    update((d) => { d.buyerCategories[selectedIndex].subcategories.splice(si, 1); });
    showToast(`"${key}" silindi`, "warn");
  }

  // Sub-subcategory
  function addSubSubcategory(si: number, key: string, labels: Labels) {
    if (selectedIndex === null) return;
    update((d) => {
      d.buyerCategories[selectedIndex].subcategories[si].subSubcategories.push({
        key, labels,
      });
    });
 
    setAddModal(null);
    showToast(`"${labels.en}" eklendi`);
  }

  function deleteSubSubcategory(si: number, ti: number) {
    if (selectedIndex === null) return;
    update((d) => {
      d.buyerCategories[selectedIndex].subcategories[si].subSubcategories.splice(ti, 1);
    });
  }

  function toggleSub(si: number) {
    setExpandedSubs((prev) => {
      const next = new Set(prev);
      if (next.has(si)) {
        next.delete(si);
      } else {
        next.add(si);
      }
      return next;
    });
  }

  // ── Stats ────────────────────────────────────────────────────────────────────

  const stats = structure
    ? structure.buyerCategories.reduce(
        (acc, c) => {
          acc.subs += c.subcategories.length;
          c.subcategories.forEach((s) => (acc.subsubs += s.subSubcategories.length));
          return acc;
        },
        { subs: 0, subsubs: 0 }
      )
    : { subs: 0, subsubs: 0 };

  const selectedCat = selectedIndex !== null ? structure?.buyerCategories[selectedIndex] : null;

  // ─────────────────────────────────────────────────────────────────────────────

  if (loading) {
    return (
      <ProtectedRoute>
        <div className="min-h-screen bg-slate-50 flex items-center justify-center">
          <div className="flex flex-col items-center gap-3">
            <div className="w-8 h-8 border-2 border-blue-500 border-t-transparent rounded-full animate-spin" />
            <p className="text-sm text-slate-500">Kategoriler yükleniyor...</p>
          </div>
        </div>
      </ProtectedRoute>
    );
  }

  return (
    <ProtectedRoute>
      <div className="min-h-screen bg-gradient-to-br from-slate-50 via-white to-slate-100">

        {/* Header */}
        <header className="bg-white/80 backdrop-blur-md border-b border-gray-200 sticky top-0 z-40">
          <div className="max-w-[1400px] mx-auto px-6 py-3 flex items-center justify-between">
            <div className="flex items-center gap-3">
              <button onClick={() => router.back()} className="p-1.5 hover:bg-gray-100 rounded-lg transition-colors">
                <ChevronLeft className="w-4 h-4 text-gray-500" />
              </button>
              <div className="w-8 h-8 bg-gradient-to-br from-blue-600 to-indigo-600 rounded-lg flex items-center justify-center shadow-sm">
                <Layers className="w-4 h-4 text-white" />
              </div>
              <div>
                <h1 className="text-sm font-bold text-gray-900 leading-tight">Kategori Yönetimi</h1>
                <p className="text-[11px] text-gray-500 leading-tight">
                  {meta ? `Son yayın: ${meta.version}` : "Henüz yayınlanmadı"}
                </p>
              </div>
            </div>
            <div className="flex items-center gap-3">
              {hasChanges && (
                <div className="flex items-center gap-1.5 text-amber-600 bg-amber-50 border border-amber-200 rounded-lg px-3 py-1.5">
                  <AlertCircle className="w-3.5 h-3.5" />
                  <span className="text-xs font-medium">Yayınlanmamış değişiklikler</span>
                </div>
              )}
              <button
                onClick={handlePublish}
                disabled={!hasChanges || publishing}
                className={`flex items-center gap-2 px-4 py-2 rounded-lg text-xs font-semibold shadow-sm transition-all ${
                  hasChanges && !publishing
                    ? "bg-gradient-to-r from-blue-600 to-indigo-600 text-white hover:from-blue-700 hover:to-indigo-700"
                    : "bg-gray-100 text-gray-400 cursor-not-allowed"
                }`}
              >
                {publishing
                  ? <div className="w-3.5 h-3.5 border-2 border-white/40 border-t-white rounded-full animate-spin" />
                  : <Upload className="w-3.5 h-3.5" />}
                {publishing ? "Yayınlanıyor..." : "Firestore'a Yayınla"}
              </button>
            </div>
          </div>
        </header>

        <main className="max-w-[1400px] mx-auto px-6 py-8">

          {/* Stats */}
          <div className="grid grid-cols-4 gap-3 mb-6">
            {[
              { label: "Alıcı Kategorileri", value: structure?.buyerCategories.length ?? 0 },
              { label: "Alt Kategoriler", value: stats.subs },
              { label: "Alt-Alt Kategoriler", value: stats.subsubs },
            ].map((s) => (
              <div key={s.label} className="bg-white border border-gray-200 rounded-xl p-4 shadow-sm">
                <div className="text-xs text-gray-500 mb-1">{s.label}</div>
                <div className="text-2xl font-bold text-gray-900">{s.value}</div>
              </div>
            ))}
            <div className="bg-white border border-gray-200 rounded-xl p-4 shadow-sm flex items-center gap-3">
              <div className={`w-2 h-2 rounded-full ${hasChanges ? "bg-amber-400" : "bg-emerald-400"}`} />
              <div>
                <div className="text-xs text-gray-500">Durum</div>
                <div className={`text-xs font-semibold ${hasChanges ? "text-amber-600" : "text-emerald-600"}`}>
                  {hasChanges ? "Yayınlanmamış" : "Güncel"}
                </div>
              </div>
            </div>
          </div>

          {/* Layout */}
          <div className="grid grid-cols-[280px_1fr] gap-4 items-start">

            {/* LEFT: Buyer category list */}
            <div className="bg-white border border-gray-200 rounded-xl overflow-hidden shadow-sm">
              <div className="flex items-center justify-between px-4 py-3 border-b border-gray-100">
                <div className="flex items-center gap-2">
                  <LayoutList className="w-4 h-4 text-gray-400" />
                  <span className="text-xs font-semibold text-gray-700">Alıcı Kategorileri</span>
                </div>
                <button
                  onClick={() => setAddModal({ type: "category" })}
                  className="flex items-center gap-1 text-[11px] text-blue-600 bg-blue-50 border border-blue-200 rounded-md px-2 py-1 hover:bg-blue-100 transition-colors font-medium"
                >
                  <Plus className="w-3 h-3" /> Ekle
                </button>
              </div>
              <div className="max-h-[600px] overflow-y-auto">
                {structure?.buyerCategories.map((cat, i) => (
                  <button
                    key={i}
                    onClick={() => { setSelectedIndex(i); setExpandedSubs(new Set()); }}
                    className={`w-full flex items-center justify-between px-4 py-3 text-left border-b border-gray-50 transition-colors group ${
                      selectedIndex === i ? "bg-blue-50" : "hover:bg-gray-50"
                    }`}
                  >
                    <div className="flex items-center gap-2.5">
                      <div className={`w-7 h-7 ${getAccent(i)} rounded-lg flex items-center justify-center text-[11px] font-bold text-white flex-shrink-0`}>
                        {cat.key.charAt(0)}
                      </div>
                      <div>
                        {/* Show all 3 language labels in sidebar */}
                        <div className="text-xs font-semibold text-gray-800">
                          {cat.labels?.tr || cat.key}
                        </div>
                        <div className="text-[10px] text-gray-400">
                          {cat.labels?.en} · {cat.subcategories.length} alt
                        </div>
                      </div>
                    </div>
                    <button
                      onClick={(e) => { e.stopPropagation(); deleteBuyerCategory(i); }}
                      className="opacity-0 group-hover:opacity-100 p-1 rounded hover:bg-red-50 hover:text-red-500 text-gray-300 transition-all"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </button>
                ))}
              </div>
            </div>

            {/* RIGHT: Editor */}
            <div className="bg-white border border-gray-200 rounded-xl shadow-sm min-h-[400px]">
              {!selectedCat ? (
                <div className="flex flex-col items-center justify-center h-[400px] text-gray-400">
                  <Layers className="w-10 h-10 mb-3 opacity-30" />
                  <p className="text-sm font-medium">Sol taraftan bir kategori seçin</p>
                </div>
              ) : (
                <>
                  {/* Editor header */}
                  <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
                    <div className="flex items-center gap-3">
                      <div className={`w-9 h-9 ${getAccent(selectedIndex!)} rounded-xl flex items-center justify-center text-sm font-bold text-white`}>
                        {selectedCat.key.charAt(0)}
                      </div>
                      <div>
                        <div className="text-sm font-bold text-gray-900">{selectedCat.key}</div>
                        <div className="text-[11px] text-gray-400">İsimleri aşağıdan düzenleyin</div>
                      </div>
                    </div>
                    <button
                      onClick={() => setAddModal({ type: "subcategory" })}
                      className="flex items-center gap-1.5 text-xs text-blue-600 bg-blue-50 border border-blue-200 rounded-lg px-3 py-2 hover:bg-blue-100 transition-colors font-semibold"
                    >
                      <Plus className="w-3.5 h-3.5" /> Alt Kategori Ekle
                    </button>
                  </div>

                  <div className="p-4 flex flex-col gap-4">

                    {/* Category labels edit */}
                    <div className="border border-dashed border-blue-200 rounded-xl p-4 bg-blue-50/30">
                      <div className="text-xs font-semibold text-blue-700 mb-2">
                        Kategori İsimleri — {selectedCat.key}
                      </div>
                      <LabelInputs
                        labels={selectedCat.labels ?? emptyLabels()}
                        onChange={(lang, value) => updateCategoryLabel(selectedIndex!, lang, value)}
                      />
                    </div>

                    {/* Subcategories */}
                    {selectedCat.subcategories.length === 0 && (
                      <div className="text-center py-6 text-gray-400 text-sm">
                        Henüz alt kategori yok.
                      </div>
                    )}

                    {selectedCat.subcategories.map((sub, si) => {
                      const isOpen = expandedSubs.has(si);
                      return (
                        <div key={si} className="border border-gray-200 rounded-xl overflow-hidden hover:border-blue-200 transition-colors">

                          {/* Sub header */}
                          <div
                            className="flex items-center gap-2 px-4 py-3 bg-gray-50 cursor-pointer select-none"
                            onClick={() => toggleSub(si)}
                          >
                            <ChevronDown className={`w-4 h-4 text-gray-400 flex-shrink-0 transition-transform ${isOpen ? "" : "-rotate-90"}`} />
                            <div className="flex-1 min-w-0">
                              <div className="text-xs font-semibold text-gray-700">
                                {sub.labels?.tr || sub.key}
                              </div>
                              <div className="text-[10px] text-gray-400">
                                {sub.labels?.en} · {sub.subSubcategories.length} öğe
                              </div>
                            </div>
                            <button
                              onClick={(e) => { e.stopPropagation(); deleteSubcategory(si); }}
                              className="p-1 hover:bg-red-50 hover:text-red-500 text-gray-300 rounded transition-colors"
                            >
                              <X className="w-3.5 h-3.5" />
                            </button>
                          </div>

                          {isOpen && (
                            <div className="px-4 py-4 border-t border-gray-100 flex flex-col gap-4">

                              {/* Subcategory labels edit */}
                              <div className="border border-dashed border-violet-200 rounded-xl p-3 bg-violet-50/30">
                                <div className="text-xs font-semibold text-violet-700 mb-2">
                                  Alt Kategori İsimleri — {sub.key}
                                </div>
                                <LabelInputs
                                  labels={sub.labels ?? emptyLabels()}
                                  onChange={(lang, value) => updateSubcategoryLabel(si, lang, value)}
                                />
                              </div>

                              {/* Sub-sub tags */}
                              <div>
                                <div className="text-xs font-semibold text-gray-500 mb-2">
                                  Alt-Alt Kategoriler
                                </div>
                                <div className="flex flex-wrap gap-1.5 mb-3">
                                  {sub.subSubcategories.length === 0 && (
                                    <span className="text-[11px] text-gray-400 italic">Henüz yok</span>
                                  )}
                                  {sub.subSubcategories.map((tag, ti) => (
                                    <span
                                      key={ti}
                                      className="inline-flex items-center gap-1.5 bg-slate-50 border border-slate-200 rounded-lg px-2.5 py-1.5 text-[11px] text-slate-600 group"
                                      title={`TR: ${tag.labels?.tr}\nEN: ${tag.labels?.en}\nRU: ${tag.labels?.ru}`}
                                    >
                                      <span className="font-medium">{tag.labels?.tr || tag.key}</span>
                                      <span className="text-slate-300">·</span>
                                      <span className="text-slate-400">{tag.labels?.en || tag.key}</span>
                                      <button
                                        onClick={() => deleteSubSubcategory(si, ti)}
                                        className="text-slate-300 hover:text-red-500 transition-colors ml-0.5"
                                      >
                                        <X className="w-3 h-3" />
                                      </button>
                                    </span>
                                  ))}
                                </div>

                                {/* Add sub-sub button */}
                                <button
                                  onClick={() => setAddModal({ type: "subsubcategory", subIdx: si })}
                                  className="flex items-center gap-1.5 text-xs text-emerald-600 bg-emerald-50 border border-emerald-200 rounded-lg px-3 py-2 hover:bg-emerald-100 transition-colors font-medium"
                                >
                                  <Plus className="w-3.5 h-3.5" />
                                  Alt-Alt Kategori Ekle
                                </button>
                              </div>
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </div>
                </>
              )}
            </div>
          </div>
        </main>

        {/* Toast */}
        {toast && (
          <div className={`fixed bottom-6 right-6 flex items-center gap-2.5 px-4 py-3 rounded-xl text-white text-sm font-medium shadow-xl z-50 ${
            toast.type === "success" ? "bg-gray-900" : "bg-amber-600"
          }`}>
            {toast.type === "success"
              ? <CheckCircle2 className="w-4 h-4 text-emerald-400" />
              : <AlertCircle className="w-4 h-4 text-white" />}
            {toast.msg}
          </div>
        )}

        {/* Add Modal */}
        {addModal && (
          <AddModal
            title={
              addModal.type === "category"
                ? "Yeni Alıcı Kategorisi"
                : addModal.type === "subcategory"
                ? "Yeni Alt Kategori"
                : "Yeni Alt-Alt Kategori"
            }
            onConfirm={(key, labels) => {
              if (addModal.type === "category") addBuyerCategory(key, labels);
              else if (addModal.type === "subcategory") addSubcategory(key, labels);
              else if (addModal.type === "subsubcategory" && addModal.subIdx !== undefined)
                addSubSubcategory(addModal.subIdx, key, labels);
            }}
            onCancel={() => setAddModal(null)}
          />
        )}

      </div>
    </ProtectedRoute>
  );
}