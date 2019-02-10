import axios from 'axios'
import { ICategoryItem } from './CategoryItem'
import category from 'client/store/modules/category';

class CategoryService {
  async getCategoryById (id: ICategoryInfo['id']): Promise<ICategoryFull> {
    const { data } = await axios.get(`api/category/${id}`, {})
    return data
  }

  async getCategoryList (): Promise<ICategoryInfo[]> {
    const { data } = await axios.get('api/categories', {})
    return data
  }

  async createCategory (
    { title, group }: { title: ICategoryInfo['title'], group: ICategoryInfo['group'] }
  ): Promise<ICategoryInfo['id']> {
    const { data } = await axios.post('api/category', null, {
      params: {
        title,
        group
      }
    })
    return data
  }

  async updateCategoryInfo (categoryId, title, group, status) {
    const { data } = await axios.post(`api/category/${categoryId}/info`, null, {
      params: {
        title,
        group,
        status
      }
    })
    return data
  }
}

export enum CategoryStatus {
  finished = 'CategoryFinished',
  inProgress = 'CategoryWIP',
  toBeWritten = 'CategoryStub'
}

export interface ICategoryInfo {
  id: string
  title: string
  created: string
  group: string
  status: CategoryStatus
}

export interface ICategoryFull {
  id: string
  title: string
  group: string
  status: CategoryStatus
  description: object
  items: ICategoryItem[]
}

const categoryServiceInstance = new CategoryService()

export { categoryServiceInstance as CategoryService }
