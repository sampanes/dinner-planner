        // Recipes and their ingredients data loaded from JSON file
        let recipes = [];
        let commonIngredients = [];

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
        
        document.addEventListener('DOMContentLoaded', async () => {
            const savedRecipes = localStorage.getItem('recipes');
            if (savedRecipes) {
                recipes = JSON.parse(savedRecipes);
            } else {
                await loadRecipes();
            }

            // Build common ingredients list
            extractCommonIngredients();
            renderRecipeList();
        });

        // Utility to extract all ingredient names
        function extractCommonIngredients() {
            const ingredientSet = new Set();

            recipes.forEach(recipe => {
                recipe.ingredients.forEach(ing => {
                    ingredientSet.add(ing.name.toLowerCase());
                });
            });

            commonIngredients = Array.from(ingredientSet);
            console.log("Common Ingredients:", commonIngredients);
        }
        
        // Render recipe list
        function renderRecipeList(filter = '') {
            recipeList.innerHTML = '';
            
            const filteredRecipes = recipes.filter(recipe => 
                recipe.name.toLowerCase().includes(filter.toLowerCase())
            );
            
            if (filteredRecipes.length === 0) {
                recipeList.innerHTML = '<p class="text-gray-500 text-center py-4">No recipes found</p>';
                return;
            }
            
            filteredRecipes.forEach(recipe => {
                const recipeCard = document.createElement('div');
                recipeCard.className = 'recipe-card bg-white p-4 rounded-lg mb-3 cursor-pointer hover:bg-gray-50 border border-gray-200';
                recipeCard.innerHTML = `
                    <div class="flex items-center gap-3">
                        ${recipe.image ? 
                            `<img src="${recipe.image}" alt="${recipe.name}" class="w-12 h-12 object-cover rounded-lg">` : 
                            `<div class="w-12 h-12 bg-gray-200 rounded-lg flex items-center justify-center">
                                <i class="fas fa-utensils text-gray-400"></i>
                            </div>`
                        }
                        <div>
                            <h3 class="font-medium text-gray-800">${recipe.name}</h3>
                            <p class="text-xs text-gray-500">${recipe.ingredients.length} ingredients</p>
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
                const matches = fuzzySearch(searchTerm, commonIngredients);
                
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
                    const amountInput = input.parentNode.nextElementSibling;
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
            
            const recipeData = {
                name,
                image: image || undefined,
                ingredients,
                instructions
            };
            
            // Check if we're editing or creating new
            const editingId = this.dataset.editingId;
            if (editingId) {
                // Update existing recipe
                const index = recipes.findIndex(r => r.id === parseInt(editingId));
                if (index !== -1) {
                    recipes[index] = {
                        ...recipes[index],
                        ...recipeData
                    };
                }
            } else {
                // Add new recipe
                const newId = recipes.length > 0 ? Math.max(...recipes.map(r => r.id)) + 1 : 1;
                recipes.push({
                    id: newId,
                    ...recipeData
                });
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