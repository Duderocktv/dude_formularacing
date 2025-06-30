// html/script.js - Final Version (Reverted Tire Element Access)

document.addEventListener('DOMContentLoaded', function() {

    // --- Define variables needed by the UPDATE functions here ---
    const kersFill = document.getElementById('kers-fill');
    const kersText = document.getElementById('kers-text');
    // *** REVERT: Define tire variables here again ***
    const tireBoxes = {
        0: document.getElementById('tire-0'), 1: document.getElementById('tire-1'),
        4: document.getElementById('tire-4'), 5: document.getElementById('tire-5')
    };
    const tirePercSpans = {
        0: tireBoxes[0]?.querySelector('.tire-perc'), 1: tireBoxes[1]?.querySelector('.tire-perc'),
        4: tireBoxes[4]?.querySelector('.tire-perc'), 5: tireBoxes[5]?.querySelector('.tire-perc')
    };
    // --- Container variables will be defined in the message listener cases ---

    console.log("Formula UI JS Loaded & DOM Ready (Final Revert).");

    // --- Update functions defined inside DOMContentLoaded ---
    function updateKersUI(data) {
        if (!kersFill || !kersText) { console.error("[UI Update] kersFill or kersText missing!"); return; }
        let text = "KERS: "; let color = "lime"; let fillPercent = 100;
        const activeDuration = data?.config?.activeDuration ?? 5000; const cooldownDuration = data?.config?.cooldownDuration ?? 30000;
        switch (data.state) {
            case "READY": text += "READY"; color = "lime"; fillPercent = 100; break;
            case "ACTIVE": text += "ACTIVE"; color = "yellow"; const cAT = typeof data.activeTimer==='number'?data.activeTimer:0; const rA = Math.max(0,activeDuration-cAT); fillPercent=(activeDuration>0)?(rA/activeDuration)*100:0; text+=` (${Math.ceil(rA/1000)}s)`; break;
            case "COOLDOWN": text += "COOLDOWN"; color = "red"; const cCT = typeof data.cooldownTimer==='number'?data.cooldownTimer:0; const rC = Math.max(0,cooldownDuration-cCT); fillPercent=(cooldownDuration>0)?(cCT/cooldownDuration)*100:0; text+=` (${Math.ceil(rC/1000)}s)`; break;
            default: text += "N/A"; color = "grey"; fillPercent = 100; break;
        }
        kersText.textContent = text; kersFill.style.backgroundColor = color; kersFill.style.width = `${fillPercent}%`;
    }

    function updateTireUI(data) {
        if (!data || !data.wear) { console.warn("[UI Update] No tire wear data received."); return; }
        const wearData = data.wear;
        const visualToGameMap = { 0: 0, 1: 1, 2: 4, 3: 5 };

        // Check if elements were found during initial load (defined in outer scope)
        if (!tireBoxes || !tireBoxes[0] || !tireBoxes[1] || !tireBoxes[4] || !tireBoxes[5] || !tirePercSpans || !tirePercSpans[0] || !tirePercSpans[1] || !tirePercSpans[4] || !tirePercSpans[5]) {
            console.error("[UI Update] Tire elements missing!");
            return;
        }

        for (let visualIndex = 0; visualIndex <= 3; visualIndex++) {
            const gameIndex = visualToGameMap[visualIndex];
            const box = tireBoxes[gameIndex]; // Use variable from outer scope
            const span = tirePercSpans[gameIndex]; // Use variable from outer scope

            if (box && span) { // Check again just in case
                const wear = typeof wearData[visualIndex] === 'number' ? wearData[visualIndex] : 100;
                span.textContent = `${Math.max(0, Math.floor(wear + 0.5))}%`;
                box.className = 'tire-box'; // Reset class
                const isBurst = data.burstStatus && typeof data.burstStatus[gameIndex] === 'boolean' ? data.burstStatus[gameIndex] : false;
                if (isBurst) { box.classList.add('tire-wear-burst'); }
                else if (wear <= 0) { box.classList.add('tire-wear-critical'); }
                else if (wear < 15) { box.classList.add('tire-wear-critical'); }
                else if (wear < 40) { box.classList.add('tire-wear-low'); }
                else if (wear < 70) { box.classList.add('tire-wear-medium'); }
                else { box.classList.add('tire-wear-good'); }
            }
        }
    }

    // Listen for messages from Lua
    window.addEventListener('message', function(event) {
        const data = event.data;
        if (!data || !data.action) { return; }

        // console.log(`[JS Received] Action: ${data.action}, Display: ${data.display}`); // Keep commented

        switch (data.action) {
            case 'showUI':
                const uiContainer = document.getElementById('formula-ui-container');
                if (uiContainer) {
                    const displayValue = (typeof data.display === 'boolean' && data.display) ? 'flex' : 'none';
                    if (displayValue === 'flex') { uiContainer.classList.add('visible-flex'); }
                    else { uiContainer.classList.remove('visible-flex'); }
                    // console.log(`[JS showUI] Toggled 'visible-flex'. Has class now? ${uiContainer.classList.contains('visible-flex')}`);
                } else { console.error("[JS showUI] uiContainer element NOT found!"); }
                break;

            case 'showKers':
                const kersContainer = document.getElementById('kers-container');
                if (kersContainer) {
                    if (typeof data.display === 'boolean' && data.display) { kersContainer.classList.add('visible'); }
                    else { kersContainer.classList.remove('visible'); }
                    // console.log(`[JS showKers] Toggled 'visible' class. Has class now? ${kersContainer.classList.contains('visible')}`);
                } else { console.error("[JS showKers] kersContainer element NOT found!"); }
                 break;

            case 'showTires':
                const tireContainer = document.getElementById('tire-container');
                 if (tireContainer) {
                    if (typeof data.display === 'boolean' && data.display) { tireContainer.classList.add('visible'); }
                    else { tireContainer.classList.remove('visible'); }
                    // console.log(`[JS showTires] Toggled 'visible' class. Has class now? ${tireContainer.classList.contains('visible')}`);
                 } else { console.error("[JS showTires] tireContainer element NOT found!"); }
                 break;

            case 'updateKers':
                 if (kersFill && kersText) { updateKersUI(data); }
                 else { console.error("[JS] Missing kersFill or kersText for updateKers!"); }
                break;

            case 'updateTires':
                 updateTireUI(data); // Relies on outer scope variables
                break;
        }
    });

    // Send nuiReady message
    const resourceName = window.GetParentResourceName ? window.GetParentResourceName() : 'dude_formularacing';
    fetch(`https://${resourceName}/nuiReady`, {
         method: 'POST',
         headers: { 'Content-Type': 'application/json; charset=UTF-8' },
         body: JSON.stringify({ message: 'NUI is ready! (Final Revert)' })
     })
    .then(() => console.log("Sent nuiReady message to Lua resource:", resourceName))
    .catch(err => console.error("Error sending nuiReady:", err));

}); // --- End of DOMContentLoaded wrapper ---