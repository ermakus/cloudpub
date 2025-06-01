import { themes as prismThemes } from "prism-react-renderer";
import type { Config } from "@docusaurus/types";
import type * as Preset from "@docusaurus/preset-classic";
import path from "path";

process.env.IS_PREACT = "false";

const config: Config = {
  title: "CloudPub",
  tagline: "From local to global with one click",
  favicon: "img/favicon.ico",

  // Set the production url of your site here
  url: "https://cloudpub.online",
  // Set the /<baseUrl>/ pathname under which your site is served
  // For GitHub pages deployment, it is often '/<projectName>/'
  baseUrl: "/docs/",

  // GitHub pages deployment config.
  // If you aren't using GitHub pages, you don't need these.
  organizationName: "cloudpub", // Usually your GitHub org/user name.
  projectName: "cloudpub", // Usually your repo name.

  onBrokenLinks: "throw",
  onBrokenMarkdownLinks: "warn",

  staticDirectories: ["public", "static"],

  // Even if you don't use internationalization, you can use this field to set
  // useful metadata like html lang. For example, if your site is Chinese, you
  // may want to replace "en" with "zh-Hans".
  i18n: {
    defaultLocale: "en",
    locales: ["en"],
  },
  plugins: [
    [
      "docusaurus-plugin-module-alias",
      {
        alias: {
          src: path.resolve(__dirname, "../../frontend/src"),
        },
      },
    ],
    [
      "docusaurus-plugin-dotenv",
      {
        path: "./.env",
        systemvars: true,
      },
    ],
  ],
  presets: [
    [
      "classic",
      {
        docs: {
          sidebarPath: "./sidebars.ts",
          routeBasePath: "/",
        },
        theme: {
          customCss: "./src/css/custom.css",
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    image: "img/welcome.png",
    navbar: {
      title: "CloudPub",
      logo: {
        alt: "CloudPub Logo",
        src: "img/logo.svg",
        href: "https://cloudpub.online",
        target: "_self",
      },
      items: [
        {
          type: "docSidebar",
          sidebarId: "tutorialSidebar",
          position: "left",
          label: "Documentation",
        },
      ],
    },
    footer: {
      style: "dark",
      copyright: `Copyright © ${new Date().getFullYear()} CloudPub`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
