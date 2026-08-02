import { defineConfig } from "vitepress";

export default defineConfig({
  title: "Pasanaku",
  description: "In-depth implementation guide for the Pasanaku rotating savings protocol",
  cleanUrls: true,
  themeConfig: {
    nav: [
      { text: "Guide", link: "/guide/overview" },
      {
        text: "Repository",
        link: "https://github.com/PasanakuOnchain/core-v2",
      },
    ],
    sidebar: [
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
