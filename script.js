        let showSalt = true;
        const EXCLUDE_INGREDIENTS = ['salt', 'pepper', 'oil', 'butter'];
        
        // Recipes and their ingredients data loaded from JSON file
        let recipes = [];
        let commonIngredientsDict = {};

        // Function to load recipes from JSON file
        async function loadRecipes() {
            try {
                const response = await fetch('recipes.json');
                if (!response.ok) {
                    throw new Error('Failed to load recipes');
                }
                recipes = await response.json();
                
                // Ensure all recipes have IDs
                recipes.forEach((recipe, index) => {
                    if (!recipe.id) {
                        recipe.id = index + 1;
                    }
                });
                                
                // Save to localStorage
                localStorage.setItem('recipes', JSON.stringify(recipes));
                
                console.log("loadRecipes called:", recipes);

                renderRecipeList();
            } catch (error) {
                console.error('Error loading recipes:', error);
                // Fallback to empty array
                recipes = [];
            }
        }
        
        // DOM elements
        const recipeList = document.getElementById('recipeList');
        const recipeDetails = document.getElementById('recipeDetails');
        const newRecipeBtn = document.getElementById('newRecipeBtn');
        const newRecipeModal = document.getElementById('newRecipeModal');
        const closeModalBtn = document.getElementById('closeModalBtn');
        const cancelRecipeBtn = document.getElementById('cancelRecipeBtn');
        const recipeForm = document.getElementById('recipeForm');
        const recipeSearch = document.getElementById('recipeSearch');
        const ingredientsContainer = document.getElementById('ingredientsContainer');
        const addIngredientBtn = document.getElementById('addIngredientBtn');
        const addIngredientPresetBtn = document.getElementById('addIngredientPresetBtn');
        
        document.addEventListener('DOMContentLoaded', async () => {
            const savedRecipes = localStorage.getItem('recipes');

            // THIS IS WHERE we load what's available for viewing
            if (savedRecipes) {
                // We have a saved recipes in local storage so just use that
                recipes = JSON.parse(savedRecipes);
            } else {
                // Brand new, so load recipes from a json file
                await loadRecipes();
            }

            extractCommonIngredientsDict();
            renderRecipeList();
            updateIngredientStats();

            // Initialize star containers with 0 rating
            renderStarRating('pinkStarContainer', 'pink', 0);
            renderStarRating('blueStarContainer', 'blue', 0);
        });

        // Utility to extract all ingredient names
        // Create a dictionary: ingredient name -> list of recipe names
        function extractCommonIngredientsDict() {
            const dict = {};

            recipes.forEach(recipe => {
                recipe.ingredients.forEach(ing => {
                    const name = ing.name.toLowerCase();
                    if (!dict[name]) {
                        dict[name] = new Set(); // Use Set to prevent duplicates
                    }
                    dict[name].add(recipe.name);
                });
            });

            // Convert sets to arrays for easier use
            commonIngredientsDict = Object.fromEntries(
                Object.entries(dict).map(([k, v]) => [k, Array.from(v)])
            );

            console.log("commonIngredientsDict:", commonIngredientsDict);
        }
        
        // Render recipe list
        function renderRecipeList(filter = '') {
            recipeList.innerHTML = '';

            const normalizedFilter = filter.toLowerCase().replace(/-/g, ' ');
            let filteredRecipes = recipes.filter(recipe => {
                const normalizedName = recipe.name.toLowerCase().replace(/-/g, ' ');
                return normalizedName.includes(normalizedFilter);
            });

            // 🧠 First: recalculate id = pinkStar + blueStar
            filteredRecipes.forEach(recipe => {
                const pink = parseInt(recipe.pinkStar) || 0;
                const blue = parseInt(recipe.blueStar) || 0;
                recipe.sortKey = pink + blue; // Don't overwrite .id if it's used elsewhere
            });

            // 🧮 Sort by sortKey (star total) descending, then name
            filteredRecipes.sort((a, b) => {
                if (b.sortKey !== a.sortKey) {
                    return b.sortKey - a.sortKey;
                }
                return a.name.localeCompare(b.name);
            });

            if (filteredRecipes.length === 0) {
                recipeList.innerHTML = '<p class="text-gray-500 text-center py-4">No recipes found</p>';
                return;
            }

            // 👇 Normal rendering logic stays unchanged
            filteredRecipes.forEach(recipe => {
                const recipeCard = document.createElement('div');
                recipeCard.className = 'recipe-card bg-white p-4 rounded-lg mb-3 cursor-pointer hover:bg-gray-50 border border-gray-200';
                recipeCard.innerHTML = `
                    <div class="flex items-start gap-3 w-full">
                        ${recipe.image ? 
                            `<img src="${recipe.image}" alt="${recipe.name}" class="w-12 h-12 object-cover rounded-lg">` : 
                            `<div class="w-12 h-12 bg-gray-200 rounded-lg flex items-center justify-center">
                                <i class="fas fa-utensils text-gray-400"></i>
                            </div>`
                        }

                        <div class="flex flex-col flex-grow">
                            <h3 class="font-medium text-gray-800">${recipe.name}</h3>
                            <div class="flex items-center justify-between">
                            <p class="text-xs text-gray-500">${recipe.ingredients.length} ingredients</p>
                                <div class="flex flex-col text-[10px] leading-none items-end">
                                    <div class="flex gap-0.5">
                                        ${'<span class="text-gray-300">★</span>'.repeat(5 - Math.min(recipe.pinkStar || 0, 5))}
                                        ${'<span class="text-pink-500">★</span>'.repeat(Math.min(recipe.pinkStar || 0, 5))}
                                    </div>
                                    <div class="flex gap-0.5">
                                        ${'<span class="text-blue-500">★</span>'.repeat(Math.min(recipe.blueStar || 0, 5))}
                                        ${'<span class="text-gray-300">★</span>'.repeat(5 - Math.min(recipe.blueStar || 0, 5))}
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                `;
                recipeCard.addEventListener('click', () => showRecipeDetails(recipe.id));
                recipeList.appendChild(recipeCard);
            });
        }
        
        // Show recipe details
        function showRecipeDetails(id) {
            const recipe = recipes.find(r => r.id === id);
            if (!recipe) return;
            
            let ingredientsHtml = '';
            recipe.ingredients.forEach(ing => {
                ingredientsHtml += `
                    <li class="flex justify-between py-1 border-b border-gray-100 last:border-0">
                        <span>${ing.name}</span>
                        <span class="text-gray-500">${ing.amount}</span>
                    </li>
                `;
            });
            
            recipeDetails.innerHTML = `
                <div>
                    <div class="flex justify-between items-start mb-6">
                        <div>
                            <h2 class="text-3xl font-bold text-gray-800 mb-2">${recipe.name}</h2>
                            <div class="flex items-center gap-2 text-sm text-gray-500">
                                <span>${recipe.ingredients.length} ingredients</span>
                                <span>•</span>
                                <button class="text-amber-600 hover:text-amber-700" onclick="editRecipe(${recipe.id})">
                                    <i class="fas fa-edit mr-1"></i> Edit
                                </button>
                                <span>•</span>
                                <button class="text-red-500 hover:text-red-600" onclick="deleteRecipe(${recipe.id})">
                                    <i class="fas fa-trash-alt mr-1"></i> Delete
                                </button>
                            </div>
                            <div class="flex gap-4 mt-2">
                                <div class="flex items-center">
                                    <span class="text-pink-500 mr-1">${recipe.pinkStar || 0}</span>
                                    <i class="fas fa-star text-pink-400"></i>
                                </div>
                                <div class="flex items-center">
                                    <span class="text-blue-500 mr-1">${recipe.blueStar || 0}</span>
                                    <i class="fas fa-star text-blue-400"></i>
                                </div>
                            </div>
                        </div>
                        ${recipe.image ? 
                            `<img src="${recipe.image}" alt="${recipe.name}" class="w-24 h-24 object-cover rounded-lg shadow">` : 
                            `<div class="w-24 h-24 bg-gray-200 rounded-lg shadow flex items-center justify-center">
                                <i class="fas fa-utensils text-3xl text-gray-400"></i>
                            </div>`
                        }
                    </div>
                    
                    <div class="grid grid-cols-1 md:grid-cols-2 gap-8 mb-8">
                        <div>
                            <h3 class="text-xl font-semibold text-gray-800 mb-3 pb-2 border-b border-gray-200">Ingredients</h3>
                            <ul class="space-y-1">
                                ${ingredientsHtml}
                            </ul>
                        </div>
                        <div>
                            <h3 class="text-xl font-semibold text-gray-800 mb-3 pb-2 border-b border-gray-200">Instructions</h3>
                            <div class="whitespace-pre-line text-gray-700">${recipe.instructions}</div>
                        </div>
                    </div>
                    
                    <div class="flex justify-end">
                        <button onclick="editRecipe(${recipe.id})" class="px-4 py-2 bg-amber-500 hover:bg-amber-600 text-white rounded-lg transition-colors">
                            <i class="fas fa-edit mr-2"></i> Edit Recipe
                        </button>
                    </div>
                </div>
            `;
        }
        
        // Edit recipe
        function editRecipe(id) {
            const recipe = recipes.find(r => r.id === id);
            if (!recipe) return;
            
            // Fill the form with recipe data
            document.getElementById('recipeName').value = recipe.name;
            document.getElementById('recipeImage').value = recipe.image || '';
            document.getElementById('recipeInstructions').value = recipe.instructions;
            
            // Clear ingredients container
            ingredientsContainer.innerHTML = '';
            
            // Add ingredients to form
            recipe.ingredients.forEach(ing => {
                addIngredientField(ing.name, ing.amount);
            });
            
            // Store the ID we're editing
            recipeForm.dataset.editingId = id;

            // Set star ratings
            renderStarRating('pinkStarContainer', 'pink', recipe.pinkStar || 0);
            renderStarRating('blueStarContainer', 'blue', recipe.blueStar || 0);

            // Show the modal
            newRecipeModal.classList.remove('hidden');  
        }
        
        // Delete recipe
        function deleteRecipe(id) {
            if (confirm('Are you sure you want to delete this recipe?')) {
                recipes = recipes.filter(r => r.id !== id);
                saveRecipes();
                renderRecipeList();
                recipeDetails.innerHTML = `
                    <div class="text-center py-20 text-gray-400">
                        <i class="fas fa-utensils text-5xl mb-4"></i>
                        <p class="text-xl">Select a recipe or create a new one</p>
                    </div>
                `;
            }
        }
        
        // Add new ingredient field
        function addIngredientField(name = '', amount = '') {
            const ingredientId = Date.now();
            const ingredientDiv = document.createElement('div');
            ingredientDiv.className = 'flex gap-2 items-center relative';
            ingredientDiv.innerHTML = `
                <div class="flex-1 relative">
                    <input type="text" 
                           class="ingredient-name w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-amber-500 focus:border-amber-500" 
                           placeholder="Ingredient" 
                           value="${name}"
                           data-id="${ingredientId}">
                </div>
                <input type="text" 
                       class="w-24 px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-amber-500 focus:border-amber-500" 
                       placeholder="Amount" 
                       value="${amount}">
                <button type="button" class="remove-ingredient text-red-500 hover:text-red-700">
                    <i class="fas fa-times"></i>
                </button>
            `;
            
            ingredientsContainer.appendChild(ingredientDiv);
            
            // Set up fuzzy search for the new ingredient field
            setupIngredientSearch(ingredientDiv.querySelector('.ingredient-name'));
        }
        
        // Setup fuzzy search for ingredient input
        function setupIngredientSearch(inputElement) {
            inputElement.addEventListener('input', function() {
                const searchTerm = this.value.toLowerCase();
                if (searchTerm.length < 2) {
                    hideSuggestions();
                    return;
                }
                
                // Find matches using fuzzy search
                const ingredientNames = Object.keys(commonIngredientsDict);
                // Pass ingredientNames into your fuzzy search algorithm
                const matches = fuzzySearch(searchTerm, ingredientNames);
                
                if (matches.length > 0) {
                    showSuggestions(this, matches);
                } else {
                    hideSuggestions();
                }
            });
            
            // Hide suggestions when clicking elsewhere
            document.addEventListener('click', function(e) {
                if (!e.target.closest('.ingredient-suggestions')) {
                    hideSuggestions();
                }
            });
        }
        
        // Fuzzy search function
        function fuzzySearch(term, list) {
            return list.filter(item => {
                const itemLower = item.toLowerCase();
                
                // Simple fuzzy matching - check if all characters appear in order
                let searchIndex = 0;
                for (let i = 0; i < itemLower.length; i++) {
                    if (itemLower[i] === term[searchIndex]) {
                        searchIndex++;
                        if (searchIndex === term.length) return true;
                    }
                }
                return false;
            }).slice(0, 5); // Limit to top 5 matches
        }
        
        // Show suggestions dropdown
        function showSuggestions(inputElement, matches) {
            // Remove any existing suggestion dropdown
            hideSuggestions();
            
            // Create a new dropdown
            const dropdown = document.createElement('div');
            dropdown.className = 'ingredient-suggestions absolute z-10 w-full mt-1 bg-white border border-gray-300 rounded-lg shadow-lg max-h-60 overflow-y-auto';
            
            const list = document.createElement('ul');
            list.className = 'py-1';
            
            matches.forEach(match => {
                const li = document.createElement('li');
                li.className = 'px-3 py-2 hover:bg-amber-50 cursor-pointer';
                li.textContent = match;
                
                // Highlight matching characters
                const highlighted = highlightMatch(match, inputElement.value.toLowerCase());
                li.innerHTML = highlighted;
                
                li.addEventListener('click', function() {
                    inputElement.value = match;
                    hideSuggestions();
                    inputElement.focus();
                });
                
                list.appendChild(li);
            });
            
            dropdown.appendChild(list);
            
            // Position the dropdown below the input
            const inputRect = inputElement.getBoundingClientRect();
            dropdown.style.position = 'absolute';
            dropdown.style.left = '0';
            dropdown.style.top = `${inputRect.height + 2}px`;
            dropdown.style.width = `${inputRect.width}px`;
            
            // Add to DOM
            inputElement.parentNode.appendChild(dropdown);
        }
        
        // Highlight matching characters
        function highlightMatch(text, searchTerm) {
            if (!searchTerm) return text;
            
            const lowerText = text.toLowerCase();
            const lowerSearch = searchTerm.toLowerCase();
            
            let result = '';
            let searchIndex = 0;
            
            for (let i = 0; i < text.length; i++) {
                if (searchIndex < lowerSearch.length && lowerText[i] === lowerSearch[searchIndex]) {
                    result += `<span class="font-bold text-amber-600">${text[i]}</span>`;
                    searchIndex++;
                } else {
                    result += text[i];
                }
            }
            
            return result;
        }
        
        // Hide suggestions dropdown
        function hideSuggestions() {
            const existing = document.querySelector('.ingredient-suggestions');
            if (existing) {
                existing.remove();
            }
        }
        
        // Save recipes to localStorage
        function saveRecipes() {
            localStorage.setItem('recipes', JSON.stringify(recipes));
            updateIngredientStats(); // Update stats whenever recipes change
        }

        // Calculate ingredient usage statistics
        function calculateIngredientStats() {
            const stats = {};
            
            recipes.forEach(recipe => {
                recipe.ingredients.forEach(ing => {
                    const name = ing.name.toLowerCase();
                    if (!showSalt && EXCLUDE_INGREDIENTS.includes(name)) return;
                    stats[name] = (stats[name] || 0) + 1;
                });
            });

            return stats;
        }

        // Update ingredient statistics display
        function updateIngredientStats(filter = '') {
            const stats = calculateIngredientStats();
            const container = document.getElementById('ingredientStatsList');
            
            // Sort by most used first
            const sortedIngredients = Object.entries(stats)
                .sort((a, b) => b[1] - a[1])
                .filter(([name]) => name.includes(filter.toLowerCase()));
            
            container.innerHTML = '';
            
            if (sortedIngredients.length === 0) {
                container.innerHTML = '<p class="text-gray-500 col-span-3 text-center py-4">No ingredients found</p>';
                return;
            }
            
            sortedIngredients.forEach(([name, count]) => {
                const card = document.createElement('div');
                card.className = 'bg-gray-50 p-4 rounded-lg border border-gray-200';
                card.innerHTML = `
                    <div class="flex justify-between items-center">
                        <span class="font-medium capitalize">${name}</span>
                        <span class="bg-amber-100 text-amber-800 text-xs font-medium px-2.5 py-0.5 rounded-full">
                            ${count} ${count === 1 ? 'recipe' : 'recipes'}
                        </span>
                    </div>
                `;
                container.appendChild(card);
            });
        }

        function renderStarRating(containerId, color, initial = 0) {
            const container = document.getElementById(containerId);
            container.innerHTML = ''; // clear previous

            for (let i = 1; i <= 5; i++) {
                const star = document.createElement('i');
                star.className = `fas fa-star text-2xl cursor-pointer transition-colors`;
                star.dataset.value = i;

                star.addEventListener('click', () => {
                    updateStarRating(containerId, i, color);
                });

                container.appendChild(star);
            }

            updateStarRating(containerId, initial, color);
        }

        function updateStarRating(containerId, value, color) {
            const container = document.getElementById(containerId);
            container.dataset.selected = value; // store current value
            const stars = container.querySelectorAll('i');

            stars.forEach((star, index) => {
                if (index < value) {
                    star.classList.add(`text-${color}-500`);
                    star.classList.remove('text-gray-300');
                } else {
                    star.classList.remove(`text-${color}-500`);
                    star.classList.add('text-gray-300');
                }
            });
        }

        function getStarValue(containerId) {
            return parseInt(document.getElementById(containerId).dataset.selected || "0");
        }
        
        // Download recipes as JSON file
        function downloadRecipes() {
            const data = JSON.stringify(recipes, null, 2);
            const blob = new Blob([data], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            
            const a = document.createElement('a');
            a.href = url;
            a.download = 'recipes.json';
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
        }

        // Event listeners
        document.getElementById('downloadRecipesBtn').addEventListener('click', downloadRecipes);
        
        // Event listeners
        newRecipeBtn.addEventListener('click', function() {
            // Reset form
            recipeForm.reset();
            ingredientsContainer.innerHTML = '';
            delete recipeForm.dataset.editingId;
            
            // Add one empty ingredient field by default
            addIngredientField();
            
            // Set default star ratings to 0
            renderStarRating('pinkStarContainer', 'pink', 0);
            renderStarRating('blueStarContainer', 'blue', 0);

            // Show modal
            newRecipeModal.classList.remove('hidden');
        });
        
        closeModalBtn.addEventListener('click', function() {
            newRecipeModal.classList.add('hidden');
        });
        
        cancelRecipeBtn.addEventListener('click', function() {
            newRecipeModal.classList.add('hidden');
        });
        
        addIngredientBtn.addEventListener('click', function() {
            addIngredientField();
        });
        
        document.getElementById('addIngredientPresetBtn').addEventListener('click', () => {
            addIngredientField('salt', 'to taste');
            addIngredientField('pepper', 'to taste');
            addIngredientField('olive oil', '1 tsp');
        });

        
        // Search ingredients stats
        document.getElementById('ingredientStatsSearch').addEventListener('input', function() {
            updateIngredientStats(this.value);
        });
        
        document.getElementById('toggleSaltBtn').addEventListener('click', function () {
            showSalt = !showSalt;
            this.textContent = showSalt ? '-common' : '+common';
            updateIngredientStats(document.getElementById('ingredientStatsSearch').value);
        });

        // Handle form submission
        recipeForm.addEventListener('submit', function(e) {
            e.preventDefault();
            
            const name = document.getElementById('recipeName').value.trim();
            const image = document.getElementById('recipeImage').value.trim();
            const instructions = document.getElementById('recipeInstructions').value.trim();
            
            // Collect ingredients
            const ingredients = [];
            const ingredientInputs = ingredientsContainer.querySelectorAll('.ingredient-name');

            ingredientInputs.forEach(input => {
                const name = input.value.trim();
                if (name) {
                    const ingredientDiv = input.closest('.flex');
                    const amountInput = ingredientDiv.querySelector('input:not(.ingredient-name)');
                    const amount = amountInput.value.trim();
                    ingredients.push({
                        name,
                        amount: amount || 'to taste'
                    });
                }
            });
            
            if (!name || !instructions || ingredients.length === 0) {
                alert('Please fill in all required fields (name, at least one ingredient, and instructions)');
                return;
            }
            
            const pinkStar = getStarValue('pinkStarContainer');
            const blueStar = getStarValue('blueStarContainer');
            const starSum = pinkStar + blueStar;

            const recipeData = {
                id: starSum,
                name,
                image: image || undefined,
                ingredients,
                instructions,
                pinkStar,
                blueStar
            };

            // Check if we're editing or creating new
            const editingId = this.dataset.editingId;
            if (editingId) {
                const index = recipes.findIndex(r => r.id === parseInt(editingId));
                if (index !== -1) {
                    recipes[index] = recipeData;  // <- no spread
                }
            } else {
                recipes.push(recipeData);  // <- just push, no manual id
            }
            
            // Save and update UI
            saveRecipes();
            renderRecipeList();
            
            // If we were editing, show the updated recipe
            if (editingId) {
                showRecipeDetails(parseInt(editingId));
            }
            
            // Close modal
            newRecipeModal.classList.add('hidden');
        });
        
        // Search recipes
        recipeSearch.addEventListener('input', function() {
            renderRecipeList(this.value);
        });
        
        // Remove ingredient field
        ingredientsContainer.addEventListener('click', function(e) {
            if (e.target.closest('.remove-ingredient')) {
                const ingredientDiv = e.target.closest('.flex.gap-2');
                if (ingredientDiv && ingredientsContainer.children.length > 1) {
                    ingredientDiv.remove();
                } else {
                    alert('A recipe needs at least one ingredient');
                }
            }
        });
        
        // Make functions available globally for inline handlers
        window.editRecipe = editRecipe;
        window.deleteRecipe = deleteRecipe;