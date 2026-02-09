# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# React (ESM from esm.sh - no build step)
pin "react", to: "https://esm.sh/react@18.3.1"
pin "react-dom/client", to: "https://esm.sh/react-dom@18.3.1/client"
pin "actioncable", to: "https://esm.sh/@rails/actioncable@7.0.0"
pin "index", to: "index.js"
