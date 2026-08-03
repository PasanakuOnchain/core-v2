import { defineConfig } from "vitepress";

export default defineConfig({
  title: "Pasanaku",
  description:
    "User guide and implementation docs for the Pasanaku rotating savings protocol",
  cleanUrls: true,
  head: [
    [
      "link",
      {
        id: "app-favicon",
        rel: "icon",
        type: "image/x-icon",
        href: "/icon.ico",
      },
    ],
    [
      "script",
      {},
      `(()=>{const e=localStorage.getItem("vitepress-theme-appearance")||"auto",a=window.matchMedia("(prefers-color-scheme: dark)").matches,d=!e||e==="auto"?a:e==="dark",f=document.getElementById("app-favicon");f&&f.setAttribute("href",d?"/icon-dark.ico":"/icon.ico")})();`,
    ],
  ],
  themeConfig: {
    nav: [
      { text: "User guide", link: "/user/getting-started" },
      { text: "Implementation", link: "/guide/overview" },
      {
        text: "Repository",
        link: "https://github.com/PasanakuOnchain/core-v2",
      },
    ],
    sidebar: [
      {
        text: "User guide",
        items: [
          { text: "Getting started", link: "/user/getting-started" },
          { text: "What is a pasanaku?", link: "/user/what-is-pasanaku" },
          { text: "Collateral", link: "/user/collateral" },
          { text: "Create and join", link: "/user/create-and-join" },
          { text: "Rounds", link: "/user/rounds" },
          { text: "Yield and end", link: "/user/yield-and-end" },
          { text: "Misses and stale pools", link: "/user/misses-and-stale" },
          { text: "Risks and fees", link: "/user/risks-and-fees" },
          { text: "Glossary", link: "/user/glossary" },
        ],
      },
      {
        text: "Implementation guide",
        items: [
          { text: "Overview", link: "/guide/overview" },
          { text: "Collateral shares", link: "/guide/collateral" },
          {
            text: "Pledge and join",
            link: "/guide/pledge-and-join",
          },
          {
            text: "Start and shuffle",
            link: "/guide/start-and-shuffle",
          },
          { text: "Rounds", link: "/guide/rounds" },
          {
            text: "Miss and reserve",
            link: "/guide/miss-and-reserve",
          },
          {
            text: "End settlement",
            link: "/guide/end-settlement",
          },
          { text: "ERC-1155 membership", link: "/guide/membership" },
          { text: "Admin and fees", link: "/guide/admin" },
          { text: "Reference", link: "/guide/reference" },
        ],
      },
    ],
    socialLinks: [],
    outline: { level: [2, 3] },
    search: { provider: "local" },
  },
});
