# Clone
- Clone https://github.com/microdevops-com/alerta-webui

# Patch
```
diff --git a/src/store/modules/customers.store.ts b/src/store/modules/customers.store.ts
index 4436f65..04f4612 100644
--- a/src/store/modules/customers.store.ts
+++ b/src/store/modules/customers.store.ts
@@ -47,7 +47,7 @@ const actions = {

 const getters = {
   customers: state => {
-    return state.customers.map(c => c.customer)
+    return state.customers.map(c => c.customer).sort()
   }
 }
```

```
diff --git a/src/components/AlertListFilter.vue b/src/components/AlertListFilter.vue
index 008482e..428cc17 100644
--- a/src/components/AlertListFilter.vue
+++ b/src/components/AlertListFilter.vue
@@ -81,7 +81,7 @@
             xs12
             class="pb-0"
           >
-            <v-select
+            <v-autocomplete
               v-model="filterCustomer"
               :items="currentCustomers"
               :menu-props="{ maxHeight: '400' }"
@@ -117,7 +117,7 @@
             xs12
             class="pb-0"
           >
-            <v-select
+            <v-autocomplete
               v-model="filterGroup"
               :items="currentGroups"
               :menu-props="{ maxHeight: '400' }"
```

# Build
- Check in Dockerfile node version (for now - 12)
- Install needed Node.js version from https://github.com/nodesource/distributions/blob/master/README.md
- `npm install`
- `npm run build`
- `cd dist; tar zcvf alerta-webui.tar.gz audio css fonts js *.html *.png *.ico`
- Copy alerta-webui.tar.gz to formula in dir with version
