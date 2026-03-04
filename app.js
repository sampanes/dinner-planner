// ========== SEEDED RNG (MULBERRY32) ==========
function mulberry32(a) {
    return function() {
        let t = a += 0x6D2B79F5;
        t = Math.imul(t ^ t >>> 15, t | 1);
        t ^= t + Math.imul(t ^ t >>> 7, t | 61);
        return ((t ^ t >>> 14) >>> 0) / 4294967296;
    }
}

function cyrb128(str) {
    let h1 = 1779033703, h2 = 3144134277,
        h3 = 1013904242, h4 = 2773480762;
    for (let i = 0, k; i < str.length; i++) {
        k = str.charCodeAt(i);
        h1 = h2 ^ Math.imul(h1 ^ k, 597399067);
        h2 = h3 ^ Math.imul(h2 ^ k, 2869860233);
        h3 = h4 ^ Math.imul(h3 ^ k, 951274213);
        h4 = h1 ^ Math.imul(h4 ^ k, 2716044179);
    }
    h1 = Math.imul(h3 ^ (h1 >>> 18), 597399067);
    h2 = Math.imul(h4 ^ (h2 >>> 22), 2869860233);
    h3 = Math.imul(h1 ^ (h3 >>> 17), 951274213);
    h4 = Math.imul(h2 ^ (h4 >>> 19), 2716044179);
    return (h1 >>> 0) + (h2 >>> 0) + (h3 >>> 0) + (h4 >>> 0);
}

function createPRNG(seedString) {
    const hash = cyrb128(seedString);
    return mulberry32(hash);
}

function fisherYatesShuffle(array, rng) {
    const shuffled = [...array];
    for (let i = shuffled.length - 1; i > 0; i--) {
        const j = Math.floor(rng() * (i + 1));
        [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
    }
    return shuffled;
}

// ========== INGREDIENT OVERLAP HELPERS ==========

// Get set of normalized ingredient names from a recipe
function getIngredientSet(recipe) {
    return new Set(recipe.ingredients.map(i => i.name.toLowerCase().trim()));
}

// Compute overlap ratio between a candidate recipe and the current plan
// Returns the fraction of the candidate's ingredients that already appear in the plan
function computeOverlap(candidateIngredients, planIngredientPool) {
    if (candidateIngredients.size === 0) return 0;
    let shared = 0;
    for (const ing of candidateIngredients) {
        if (planIngredientPool.has(ing)) shared++;
    }
    return shared / candidateIngredients.size;
}

// ========== URL STATE MANAGEMENT ==========
function parseHashParams() {
    const hash = window.location.hash || '#/app';
    const queryIndex = hash.indexOf('?');
    // FIXED: index is a number, not a string "-1"
    const queryString = queryIndex !== -1 ? hash.substring(queryIndex + 1) : '';
    const params = new URLSearchParams(queryString);

    return {
        // Just use the relative path string; fetch() handles the rest
        src: params.get('src') || 'recipes.json',
        seed: params.get('seed') || generateRandomSeed(),
        meals: Math.min(7, Math.max(3, parseInt(params.get('meals')) || 6)),
        overlap: Math.min(100, Math.max(0, parseInt(params.get('overlap')) || 0)),
        locks: (params.get('lock') || '').split('|').filter(Boolean).slice(0, 3)
    };
}

function updateHashParams(state) {
    const params = new URLSearchParams();
    params.set('src', state.src);
    params.set('seed', state.seed);
    params.set('meals', state.meals.toString());
    params.set('overlap', state.overlap.toString());
    if (state.locks.length > 0) {
        params.set('lock', state.locks.join('|'));
    }
    window.location.hash = `/app?${params.toString()}`;
}

function generateRandomSeed() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    const array = new Uint8Array(6);
    crypto.getRandomValues(array);
    let seed = 'KUR';
    for (let i = 0; i < 6; i++) {
        seed += chars[array[i] % chars.length];
    }
    return seed;
}

// ========== APP STATE ==========
let appState = {
    recipes: [],
    plan: [],
    src: '',
    seed: '',
    meals: 6,
    overlap: 0,
    locks: [],
    loading: true,
    error: null
};

// ========== DOM ELEMENTS ==========
const elements = {
    seedInput: document.getElementById('seedInput'),
    mealsSlider: document.getElementById('mealsSlider'),
    mealsValue: document.getElementById('mealsValue'),
    overlapSlider: document.getElementById('overlapSlider'),
    overlapValue: document.getElementById('overlapValue'),
    overlapHint: document.getElementById('overlapHint'),
    shuffleBtn: document.getElementById('shuffleBtn'),
    copyLinkBtn: document.getElementById('copyLinkBtn'),
    resetBtn: document.getElementById('resetBtn'),
    retryBtn: document.getElementById('retryBtn'),
    loading: document.getElementById('loading'),
    errorCard: document.getElementById('errorCard'),
    errorUrl: document.getElementById('errorUrl'),
    planSection: document.getElementById('planSection'),
    planList: document.getElementById('planList'),
    planCount: document.getElementById('planCount'),
    planTheme: document.getElementById('planTheme'),
    grocerySection: document.getElementById('grocerySection'),
    groceryPanel: document.getElementById('groceryPanel'),
    groceryList: document.getElementById('groceryList'),
    toggleGroceryBtn: document.getElementById('toggleGroceryBtn'),
    copyGroceryBtn: document.getElementById('copyGroceryBtn'),
    recipeModal: document.getElementById('recipeModal'),
    modalTitle: document.getElementById('modalTitle'),
    modalImage: document.getElementById('modalImage'),
    modalStars: document.getElementById('modalStars'),
    modalIngredients: document.getElementById('modalIngredients'),
    closeModalBtn: document.getElementById('closeModalBtn')
};

// ========== RECIPE FETCHING ==========
async function fetchRecipes(url) {
    try {
        const response = await fetch(url);
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        return await response.json();
    } catch (error) {
        throw new Error(`Failed to fetch recipes: ${error.message}`);
    }
}

// ========== PLAN GENERATION ==========
function generatePlan() {
    const { recipes, meals, locks, seed, overlap } = appState;
    const overlapThreshold = overlap / 100; // convert 0-100 to 0.0-1.0

    // 1. Resolve locked recipe objects by name (exact match)
    const lockedRecipes = locks
        .map(name => recipes.find(r => r.name === name))
        .filter(Boolean);
    
    // 2. Start plan with locked recipes
    let plan = [...lockedRecipes];

    // 3. Build the ingredient pool from locked recipes
    const planIngredientPool = new Set();
    for (const r of plan) {
        for (const ing of getIngredientSet(r)) {
            planIngredientPool.add(ing);
        }
    }
    
    // 4. Create candidate pool (exclude already-locked recipes)
    const lockedNames = new Set(locks);
    const candidates = recipes.filter(r => !lockedNames.has(r.name));
    
    // 5. Deterministically shuffle candidates using seeded PRNG
    const rng = createPRNG(seed);
    const shuffledCandidates = fisherYatesShuffle(candidates, rng);

    // 6. Fill plan greedily, checking overlap threshold for each candidate
    for (const candidate of shuffledCandidates) {
        if (plan.length >= meals) break;

        const candidateIngredients = getIngredientSet(candidate);

        // If the plan is empty (no locked recipes) and overlap > 0,
        // accept the first candidate unconditionally as the "seed meal"
        if (planIngredientPool.size === 0 || overlapThreshold === 0) {
            // No overlap filtering needed (either no reference pool or overlap is 0)
            plan.push(candidate);
            for (const ing of candidateIngredients) {
                planIngredientPool.add(ing);
            }
        } else {
            // Check if candidate meets the overlap requirement
            const overlapRatio = computeOverlap(candidateIngredients, planIngredientPool);
            if (overlapRatio >= overlapThreshold) {
                plan.push(candidate);
                for (const ing of candidateIngredients) {
                    planIngredientPool.add(ing);
                }
            }
            // If not enough overlap, skip this candidate (plan may end up smaller)
        }
    }
    
    appState.plan = plan;
    return plan;
}

// ========== INTELLIGENT THEME DETECTION ==========
function detectTheme(plan) {
    if (!plan || plan.length === 0) return null;
    
    // Collect all ingredients across all planned recipes
    const allIngredients = new Set();
    const ingredientCounts = new Map();
    
    plan.forEach(recipe => {
        recipe.ingredients.forEach(ing => {
            const name = ing.name.toLowerCase().trim();
            allIngredients.add(name);
            ingredientCounts.set(name, (ingredientCounts.get(name) || 0) + 1);
        });
    });
    
    // Define cuisine/theme patterns with their characteristic ingredients
    const cuisinePatterns = {
        'Italian': ['pasta', 'tomato', 'basil', 'oregano', 'parmesan', 'mozzarella', 'garlic', 'olive oil', 'breadcrumbs', 'lasagna', 'risotto', 'pizza', 'spaghetti', 'marinara', 'alfredo', 'pesto', 'ricotta', 'prosciutto', 'salami', 'pepperoni', 'anchovy', 'olive', 'capers', 'wine', 'rosemary', 'thyme', 'sage', 'focaccia', 'ciabatta'],
        'Asian': ['soy sauce', 'ginger', 'rice', 'sesame', 'teriyaki', 'sriracha', 'miso', 'noodle', 'wok', 'bok choy', 'shiitake', 'edamame', 'tofu', 'soybean', 'fish sauce', 'curry', 'coconut milk', 'lime', 'lemongrass', 'chili', 'garlic', 'scallion', 'ginger', 'rice vinegar', 'mirin', 'sake', 'ramen', 'udon', 'sushi', 'tempura', 'teriyaki', 'stir fry', 'wonton', 'dim sum', 'pho', 'banh mi', 'kimchi', 'gochujang', 'sesame oil'],
        'Mexican': ['tortilla', 'cilantro', 'lime', 'jalapeño', 'cumin', 'beans', 'cheese', 'salsa', 'guacamole', 'avocado', 'chipotle', 'taco', 'burrito', 'enchilada', 'quesadilla', 'fajita', 'tamale', 'chili powder', 'paprika', 'oregano', 'sour cream', 'refried', 'rice', 'corn', 'serrano', 'onion', 'garlic', 'tomato', 'lime', 'cilantro', 'pepper'],
        'Indian': ['curry', 'turmeric', 'garam masala', 'cumin', 'coriander', 'lentil', 'paneer', 'garlic', 'ginger', 'onion', 'tomato', 'cilantro', 'mint', 'chili', 'cardamom', 'clove', 'cinnamon', 'bay leaf', 'mustard seed', 'fenugreek', 'saffron', 'ghee', 'butter', 'cream', 'yogurt', 'naan', 'basmati', 'biryani', 'tikka', 'masala', 'dhal', 'samosa', 'pakora', 'tandoori', 'korma', 'biryani'],
        'Mediterranean': ['olive oil', 'lemon', 'feta', 'cucumber', 'hummus', 'chickpea', 'parsley', 'tomato', 'garlic', 'onion', 'bell pepper', 'eggplant', 'zucchini', 'lamb', 'chicken', 'fish', 'yogurt', 'tzatziki', 'tabbouleh', 'falafel', 'pita', 'bread', 'focaccia', 'bruschetta', 'caprese', 'antipasto', 'grape leaf', 'artichoke', 'olive', 'feta', 'goat cheese'],
        'American': ['burger', 'fries', 'bacon', 'cheese', 'ketchup', 'mustard', 'mayo', 'lettuce', 'tomato', 'onion', 'pickle', 'bun', 'steak', 'bbq', 'ribs', 'brisket', 'mac and cheese', 'casserole', 'mashed potato', 'corn', 'green bean', 'apple pie', 'brownie', 'cookie', 'pancake', 'waffle', 'syrup', 'batter', 'bread crumbs'],
        'Breakfast': ['egg', 'bacon', 'sausage', 'pancake', 'waffle', 'cereal', 'oatmeal', 'toast', 'bagel', 'cream cheese', 'butter', 'syrup', 'fruit', 'banana', 'berry', 'yogurt', 'granola', 'muffin', 'croissant', 'quiche', 'scramble', 'omelet', 'hash brown', 'home fry', 'avocado', 'salmon', 'lox', 'capers', 'red onion'],
        'Comfort Food': ['mac and cheese', 'grilled cheese', 'soup', 'casserole', 'pot pie', 'meatloaf', 'mashed potato', 'gravy', 'cream', 'butter', 'cheese', 'cream of mushroom', 'cream of chicken', 'noodle', 'bread', 'potato', 'chicken', 'beef', 'pork', 'slow cook', 'one pot', 'sticky', 'rich', 'hearty'],
        'Healthy': ['salad', 'greens', 'spinach', 'kale', 'arugula', 'lettuce', 'cucumber', 'tomato', 'carrot', 'broccoli', 'cauliflower', 'bell pepper', 'avocado', 'quinoa', 'brown rice', 'chicken breast', 'salmon', 'tuna', 'egg white', 'tofu', 'legume', 'bean', 'lentil', 'chickpea', 'fruit', 'vegetable', 'lemon', 'vinegar', 'dressing', 'light'],
        'Seafood': ['salmon', 'shrimp', 'fish', 'crab', 'lobster', 'scallop', 'clam', 'mussel', 'oyster', 'tuna', 'cod', 'tilapia', 'halibut', 'trout', 'anchovy', 'sardine', 'sea bass', 'mahi', 'swordfish', 'squid', 'calamari', 'octopus', 'coconut shrimp', 'fish and chips', 'cioppino', 'paella', 'bouillabaisse', 'lobster roll', 'crab cake'],
        'BBQ & Grill': ['bbq', 'barbecue', 'grill', 'smoke', 'ribs', 'brisket', 'pulled pork', 'chicken', 'burger', 'steak', 'hot dog', 'sausage', 'kebab', 'sauce', 'rub', 'marinade', 'smoky', 'char', 'grill', 'pit', 'smoker', ' BBQ sauce', 'coleslaw', 'cornbread', ' baked bean', 'pickle', 'onion'],
        'Soup & Stew': ['soup', 'stew', 'broth', 'stock', 'chicken', 'beef', 'pork', 'vegetable', 'noodle', 'rice', 'bean', 'lentil', 'potato', 'carrot', 'celery', 'onion', 'garlic', 'tomato', 'cream', 'herbs', 'thyme', 'bay leaf', 'rosemary', 'slow cook', 'crockpot', 'chili', 'gumbo', 'chowder', 'minestrone', 'potage'],
        'Spicy': ['hot', 'spicy', 'jalapeño', 'serrano', 'habanero', 'cayenne', 'chili', 'pepper', 'sriracha', 'tabasco', 'wasabi', 'ginger', 'garlic', 'curry', 'cumin', 'paprika', 'cayenne', 'red pepper', 'chipotle', 'ghost pepper', 'scorpion', 'carolina reaper', 'thai', 'indian', 'mexican', 'korean', 'szechuan', 'fire', 'heat'],
        'Vegetarian': ['tofu', 'tempeh', 'seitan', 'eggplant', 'mushroom', 'spinach', 'kale', 'chickpea', 'black bean', 'lentil', 'quinoa', 'rice', 'pasta', 'vegetable', 'cheese', 'egg', 'milk', 'cream', 'butter', 'plant-based', 'meatless', 'veggie', 'vegetable broth', 'nut', 'almond', 'cashew', 'walnut', 'pecan', 'avocado', 'hummus'],
        'Light & Fresh': ['lettuce', 'spinach', 'arugula', 'kale', 'cucumber', 'tomato', 'avocado', 'lemon', 'lime', 'orange', 'grapefruit', 'berry', 'melon', 'fruit', 'fresh', 'raw', 'light', 'crisp', 'citrus', 'herbs', 'mint', 'basil', 'cilantro', 'parsley', 'dill', 'chive', 'green', 'salad', 'vinaigrette', 'dressing'],
        'Rich & Decadent': ['butter', 'cream', 'cheese', 'bacon', 'truffle', 'lobster', 'filet', 'ribeye', 'pork belly', 'duck', 'foie gras', 'heavy cream', 'sour cream', 'cream cheese', 'parmesan', 'gorgonzola', 'truffle oil', 'wine', 'brandy', 'champagne', 'chocolate', 'caramel', 'butterscotch', 'dulce de leche', 'ganache', 'fondant', 'aussie'],
        'Quick & Easy': ['minute', 'quick', 'easy', 'simple', 'fast', 'one pan', 'one', 'sheet pot pan', 'stir fry', 'microwave', 'premade', 'package', 'box', 'frozen', 'canned', 'jar', 'mix', 'instant', 'ready', '5 minute', '10 minute', '15 minute', '30 minute', 'no cook', 'cold', 'assemble', 'combine', 'mix'],
        'Farm to Table': ['farm', 'fresh', 'local', 'seasonal', 'organic', 'garden', 'heirloom', 'ripe', 'vine', 'tree', 'root', 'herb', 'rosemary', 'thyme', 'sage', 'oregano', 'basil', 'mint', 'dill', 'parsley', 'cilantro', 'chive', 'scallion', 'shallot', 'leek', 'radish', 'beet', 'carrot', 'turnip', 'squash', 'zucchini'],
        'Pasta & Noodles': ['pasta', 'noodle', 'spaghetti', 'penne', 'fettuccine', 'rigatoni', 'lasagna', 'macaroni', 'linguine', 'vermicelli', 'ramen', 'udon', 'soba', 'rice noodle', 'lo mein', 'pho', 'carbonara', 'alfredo', 'marinara', 'pesto', 'bolognese', 'meatball', 'clam sauce', 'pomodoro', 'aglio e olio', 'noodle', 'stir fry', 'lo mein', 'pad thai', 'yakisoba']
    };
    
    // Calculate scores for each cuisine
    const scores = {};
    const totalIngredients = allIngredients.size;
    
    for (const [cuisine, ingredients] of Object.entries(cuisinePatterns)) {
        let matchCount = 0;
        let weightedCount = 0;
        
        for (const ingredient of allIngredients) {
            for (const pattern of ingredients) {
                if (ingredient.includes(pattern) || pattern.includes(ingredient)) {
                    const count = ingredientCounts.get(ingredient) || 1;
                    matchCount++;
                    weightedCount += count;
                    break;
                }
            }
        }
        
        // Calculate score with weighting based on ingredient frequency
        if (matchCount > 0) {
            // Normalize by total ingredients and give bonus for multiple matching ingredients
            scores[cuisine] = {
                raw: matchCount,
                weighted: weightedCount,
                ratio: matchCount / totalIngredients
            };
        }
    }
    
    // Get the top matching cuisines
    const sortedCuisines = Object.entries(scores)
        .sort((a, b) => {
            // Prioritize both weighted count and ratio
            const scoreA = a[1].weighted * 0.7 + (a[1].ratio * 100) * 0.3;
            const scoreB = b[1].weighted * 0.7 + (b[1].ratio * 100) * 0.3;
            return scoreB - scoreA;
        })
        .filter(([_, data]) => data.raw >= 2 || data.weighted >= 3); // Minimum threshold
    
    // Determine the main theme
    let theme = null;
    let themeIcon = '🍽️';
    
    if (sortedCuisines.length > 0) {
        const topCuisine = sortedCuisines[0][0];
        
        // Map cuisine to display name and icon
        const cuisineDisplay = {
            'Italian': { name: '🍝 Italian Night', icon: '🍝' },
            'Asian': { name: '🥡 Asian Fusion', icon: '🥡' },
            'Mexican': { name: '🌮 Taco Fiesta', icon: '🌮' },
            'Indian': { name: '🍛 Curry House', icon: '🍛' },
            'Mediterranean': { name: '🫒 Mediterranean', icon: '🫒' },
            'American': { name: '🍔 All-American', icon: '🍔' },
            'Breakfast': { name: '☕ Breakfast Club', icon: '☕' },
            'Comfort Food': { name: '🍲 Comfort Classics', icon: '🍲' },
            'Healthy': { name: '🥗 Fresh & Healthy', icon: '🥗' },
            'Seafood': { name: '🦐 Seafood Feast', icon: '🦐' },
            'BBQ & Grill': { name: '🔥 BBQ & Grilling', icon: '🔥' },
            'Soup & Stew': { name: '🥣 Soups & Stews', icon: '🥣' },
            'Spicy': { name: '🌶️ Spicy Kick', icon: '🌶️' },
            'Vegetarian': { name: '🥬 Meatless Meals', icon: '🥬' },
            'Light & Fresh': { name: '💚 Light & Fresh', icon: '💚' },
            'Rich & Decadent': { name: '✨ Rich & Decadent', icon: '✨' },
            'Quick & Easy': { name: '⚡ Quick & Easy', icon: '⚡' },
            'Farm to Table': { name: '🌿 Farm Fresh', icon: '🌿' },
            'Pasta & Noodles': { name: '🍜 Pasta & Noodles', icon: '🍜' }
        };
        
        const display = cuisineDisplay[topCuisine] || { name: topCuisine, icon: '🍽️' };
        theme = display.name;
        themeIcon = display.icon;
        
        // Check if we have a second strong match to blend themes
        if (sortedCuisines.length >= 2 && sortedCuisines[1][1].weighted >= sortedCuisines[0][1].weighted * 0.6) {
            const secondCuisine = sortedCuisines[1][0];
            const secondDisplay = cuisineDisplay[secondCuisine] || { name: secondCuisine, icon: '🍽️' };
            // Create a blended theme name
            if (topCuisine === 'Healthy' && secondCuisine === 'Asian') {
                theme = '🥗 Asian-Inspired Healthy';
                themeIcon = '🥗';
            } else if (topCuisine === 'Comfort Food' && secondCuisine === 'Italian') {
                theme = '🍝 Italian Comfort';
                themeIcon = '🍝';
            } else if (topCuisine === 'Seafood' && secondCuisine === 'Mediterranean') {
                theme = '🐟 Mediterranean Seafood';
                themeIcon = '🐟';
            }
        }
    }
    
    // Fallback: analyze by ingredient diversity and commonality
    if (!theme) {
        const uniqueIngredients = allIngredients.size;
        const avgFrequency = plan.length * (plan[0]?.ingredients?.length || 1) / uniqueIngredients;
        
        if (avgFrequency > 2.5) {
            theme = '🔄 Batch Cook Friendly';
            themeIcon = '🔄';
        } else if (uniqueIngredients < 8) {
            theme = '🎯 Simple & Focused';
            themeIcon = '🎯';
        } else if (uniqueIngredients > 20) {
            theme = '🌈 Variety Pack';
            themeIcon = '🌈';
        } else {
            theme = '🍽️ Mixed Menu';
            themeIcon = '🍽️';
        }
    }
    
    return { theme, icon: themeIcon };
}

// ========== GROCERY LIST ==========
function generateGroceryList() {
    const { plan } = appState;
    const groceryMap = new Map();
    
    plan.forEach(recipe => {
        recipe.ingredients.forEach(ing => {
            const name = ing.name.toLowerCase();
            if (!groceryMap.has(name)) {
                groceryMap.set(name, {
                    name: ing.name,
                    amounts: [],
                    mealCount: 0
                });
            }
            const item = groceryMap.get(name);
            item.amounts.push(ing.amount);
            item.mealCount++;
        });
    });
    
    return Array.from(groceryMap.values())
        .sort((a, b) => a.name.localeCompare(b.name));
}

function groceryListToText(groceryList) {
    return groceryList
        .map(item => `${item.name}: ${item.amounts.join(' + ')} (used in ${item.mealCount} meal${item.mealCount > 1 ? 's' : ''})`)
        .join('\n');
}

// ========== RENDER FUNCTIONS ==========
function renderStars(pinkStar, blueStar) {
    return `
        <div class="star-group">
            <span class="star-pink">💖</span>
            <span>${pinkStar}</span>
        </div>
        <div class="star-group">
            <span class="star-blue">💙</span>
            <span>${blueStar}</span>
        </div>
    `;
}

function renderImage(imageUrl, recipeName) {
    return `
        <div class="recipe-image">
            <img 
                src="${imageUrl}" 
                alt="${recipeName}"
                onerror="this.parentElement.innerHTML='<div class=\\'placeholder\\'>🍽️</div>'"
            >
        </div>
    `;
}

function renderRecipeCard(recipe, index) {
    const isLocked = appState.locks.includes(recipe.name);
    
    return `
        <div class="recipe-card ${isLocked ? 'locked' : ''}" data-index="${index}">
            ${renderImage(recipe.image, recipe.name)}
            <div class="recipe-content">
                <h3 class="recipe-name">${recipe.name}</h3>
                <div class="recipe-stars">
                    ${renderStars(recipe.pinkStar, recipe.blueStar)}
                </div>
                <div class="recipe-actions">
                    <button class="lock-btn ${isLocked ? 'locked' : 'unlocked'}" data-name="${encodeURIComponent(recipe.name)}">
                        ${isLocked ? '🔒 Locked' : '🔓 Lock'}
                    </button>
                </div>
            </div>
        </div>
    `;
}

function renderPlan() {
    // Detect and display theme
    const themeData = detectTheme(appState.plan);
    if (themeData) {
        elements.planTheme.innerHTML = `
            <span class="theme-icon">${themeData.icon}</span>
            <div>
                <span class="theme-label">Menu Theme:</span>
                <span class="theme-value">${themeData.theme}</span>
            </div>
        `;
    } else {
        elements.planTheme.innerHTML = '';
    }

    if (appState.plan.length === 0) {
        elements.planList.innerHTML = '<p style="text-align:center;color:var(--text-secondary);padding:20px;">No recipes match the overlap requirement. Try lowering the overlap slider.</p>';
        elements.planCount.textContent = '(0 meals)';
        return;
    }

    const { plan, meals, overlap } = appState;
    if (plan.length < meals && overlap > 0) {
        elements.planCount.textContent = `(${plan.length} of ${meals} — overlap filtered)`;
    } else {
        elements.planCount.textContent = `(${plan.length} meals)`;
    }
    
    elements.planList.innerHTML = appState.plan.map(renderRecipeCard).join('');
    
    elements.planList.querySelectorAll('.recipe-card').forEach(card => {
        card.addEventListener('click', (e) => {
            if (e.target.closest('.lock-btn')) return;
            const index = parseInt(card.dataset.index);
            openModal(appState.plan[index]);
        });
    });
    
    elements.planList.querySelectorAll('.lock-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
            e.stopPropagation();
            const name = decodeURIComponent(btn.dataset.name);
            toggleLock(name);
        });
    });
}

function renderGroceryList() {
    const groceryList = generateGroceryList();
    
    if (groceryList.length === 0) {
        elements.groceryList.innerHTML = '<p style="color:var(--text-secondary);text-align:center;">No ingredients needed</p>';
        return;
    }
    
    elements.groceryList.innerHTML = groceryList.map(item => `
        <div class="grocery-item">
            <div class="grocery-name">${item.name}</div>
            <div class="grocery-amount">${item.amounts.join(' + ')}</div>
            <div class="grocery-count">used in ${item.mealCount} meal${item.mealCount > 1 ? 's' : ''}</div>
        </div>
    `).join('');
}

function getOverlapHintText(value) {
    if (value === 0) return 'No grouping';
    if (value <= 15) return 'Minimal overlap';
    if (value <= 30) return 'Light overlap';
    if (value <= 50) return 'Moderate overlap';
    if (value <= 70) return 'Strong overlap';
    if (value <= 90) return 'Very strict';
    return 'Near-identical ingredients';
}

function renderUI() {
    const { loading, error, plan, meals, seed, locks, overlap } = appState;
    
    elements.loading.classList.toggle('hidden', !loading);
    elements.errorCard.classList.toggle('hidden', !error);
    elements.planSection.classList.toggle('hidden', loading || !!error);
    elements.grocerySection.classList.toggle('hidden', loading || !!error);
    
    if (error) {
        elements.errorUrl.textContent = appState.src;
    }
    
    elements.seedInput.value = seed;
    elements.mealsSlider.value = meals;
    elements.mealsValue.textContent = meals;
    elements.overlapSlider.value = overlap;
    elements.overlapValue.textContent = overlap;
    elements.overlapHint.textContent = getOverlapHintText(overlap);
}

// ========== MODAL ==========
function openModal(recipe) {
    elements.modalTitle.textContent = recipe.name;
    
    elements.modalImage.innerHTML = `
        <img 
            src="${recipe.image}" 
            alt="${recipe.name}"
            onerror="this.parentElement.innerHTML='<div class=\\'placeholder\\'>🍽️</div>'"
        >
    `;
    
    elements.modalStars.innerHTML = renderStars(recipe.pinkStar, recipe.blueStar);
    
    elements.modalIngredients.innerHTML = recipe.ingredients.map(ing => 
        `<li><span class="amount">${ing.amount}</span> ${ing.name}</li>`
    ).join('');
    
    elements.recipeModal.classList.remove('hidden');
    document.body.style.overflow = 'hidden';
}

function closeModal() {
    elements.recipeModal.classList.add('hidden');
    document.body.style.overflow = '';
}

// ========== TOAST NOTIFICATION ==========
function showToast(message) {
    let toast = document.querySelector('.toast');
    if (!toast) {
        toast = document.createElement('div');
        toast.className = 'toast';
        document.body.appendChild(toast);
    }
    toast.textContent = message;
    toast.classList.add('show');
    setTimeout(() => toast.classList.remove('show'), 2000);
}

// ========== STATE ACTIONS ==========
function toggleLock(recipeName) {
    const locks = [...appState.locks];
    const index = locks.indexOf(recipeName);
    
    if (index !== -1) {
        locks.splice(index, 1);
    } else {
        if (locks.length >= 3) {
            showToast('Maximum 3 locks allowed');
            return;
        }
        locks.push(recipeName);
    }
    
    appState.locks = locks;
    updateHashParams(appState);
    generatePlan();
    renderPlan();
    renderGroceryList();
}

function shuffleNewSeed() {
    appState.seed = generateRandomSeed();
    updateHashParams(appState);
    generatePlan();
    renderPlan();
    renderGroceryList();
    renderUI();
}

function resetAll() {
    appState.seed = generateRandomSeed();
    appState.meals = 6;
    appState.overlap = 0;
    appState.locks = [];
    updateHashParams(appState);
    generatePlan();
    renderPlan();
    renderGroceryList();
    renderUI();
}

function updateMealsCount(value) {
    const meals = Math.min(7, Math.max(3, parseInt(value) || 6));
    appState.meals = meals;
    elements.mealsValue.textContent = meals;
    updateHashParams(appState);
    generatePlan();
    renderPlan();
    renderGroceryList();
}

function updateOverlap(value) {
    const overlap = Math.min(100, Math.max(0, parseInt(value) || 0));
    appState.overlap = overlap;
    elements.overlapValue.textContent = overlap;
    elements.overlapHint.textContent = getOverlapHintText(overlap);
    updateHashParams(appState);
    generatePlan();
    renderPlan();
    renderGroceryList();
}

async function copyLink() {
    try {
        await navigator.clipboard.writeText(window.location.href);
        showToast('Link copied!');
    } catch {
        const textArea = document.createElement('textarea');
        textArea.value = window.location.href;
        document.body.appendChild(textArea);
        textArea.select();
        document.execCommand('copy');
        document.body.removeChild(textArea);
        showToast('Link copied!');
    }
}

async function copyGroceryList() {
    try {
        const groceryList = generateGroceryList();
        const text = groceryListToText(groceryList);
        await navigator.clipboard.writeText(text);
        showToast('Grocery list copied!');
    } catch {
        showToast('Failed to copy');
    }
}

// ========== INITIALIZATION ==========
async function init() {
    const params = parseHashParams();
    appState.src = params.src;
    appState.seed = params.seed;
    appState.meals = params.meals;
    appState.overlap = params.overlap;
    appState.locks = params.locks;
    appState.loading = true;
    appState.error = null;
    
    renderUI();
    
    try {
        appState.recipes = await fetchRecipes(appState.src);
        appState.loading = false;
        generatePlan();
        renderPlan();
        renderGroceryList();
        renderUI();
    } catch (error) {
        appState.loading = false;
        appState.error = error.message;
        renderUI();
    }
}

// ========== EVENT LISTENERS ==========
elements.shuffleBtn.addEventListener('click', shuffleNewSeed);
elements.resetBtn.addEventListener('click', resetAll);
elements.copyLinkBtn.addEventListener('click', copyLink);
elements.retryBtn.addEventListener('click', init);
elements.closeModalBtn.addEventListener('click', closeModal);
elements.copyGroceryBtn.addEventListener('click', copyGroceryList);

elements.toggleGroceryBtn.addEventListener('click', () => {
    elements.groceryPanel.classList.toggle('hidden');
});

elements.recipeModal.addEventListener('click', (e) => {
    if (e.target === elements.recipeModal) {
        closeModal();
    }
});

elements.mealsSlider.addEventListener('input', (e) => {
    updateMealsCount(e.target.value);
});

elements.overlapSlider.addEventListener('input', (e) => {
    updateOverlap(e.target.value);
});

window.addEventListener('hashchange', init);

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !elements.recipeModal.classList.contains('hidden')) {
        closeModal();
    }
});

// Start app
init();
