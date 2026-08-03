<script setup lang="ts">
import DefaultTheme from "vitepress/theme";
import { inBrowser, useData } from "vitepress";
import { watchEffect } from "vue";

const { isDark } = useData();

watchEffect(() => {
  if (!inBrowser) return;
  const favicon = document.getElementById("app-favicon");
  if (favicon instanceof HTMLLinkElement) {
    favicon.href = isDark.value ? "/icon-dark.ico" : "/icon.ico";
  }
});
</script>

<template>
  <DefaultTheme.Layout />
</template>
